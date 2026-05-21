-- =========================================================
-- FILE: 07_dw_star_schema.sql
-- PROJECT: Google Play Store Data Warehouse
-- PHASE: Phase 2 - Data Warehouse Star Schema
-- PURPOSE:
--   Build the logical star schema on Supabase/PostgreSQL.
--   This schema implements the Phase 1 star schema:
--     - fact_app_snapshot
--     - dim_app
--     - dim_category
--     - dim_app_type
--     - dim_content_rating
--     - dim_last_updated_date
--     - dim_genre
--     - bridge_app_snapshot_genre with weight
--
-- RUN AFTER:
--   01_reconciled_schema.sql
--   02_domain_load.sql
--   03_app_snapshot_etl.sql
--   04_genre_etl.sql
--   05_dqa_queries.sql
--   06_cleaning_and_audit.sql
-- =========================================================

begin;

-- =========================================================
-- 0. RESET DW SCHEMA ONLY
-- =========================================================
-- This does not touch raw, reconciled, dq, or clean schemas.

drop schema if exists dw cascade;
create schema dw;


-- =========================================================
-- 1. DIMENSION: APP
-- =========================================================

create table dw.dim_app (
    app_key bigint generated always as identity primary key,
    app_id bigint not null,
    app_name text not null,

    -- Useful lineage / normalization attribute
    app_name_norm text,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_app_app_id unique (app_id)
);

create index idx_dim_app_name
    on dw.dim_app(app_name);


-- =========================================================
-- 2. DIMENSION: CATEGORY
-- =========================================================

create table dw.dim_category (
    category_key bigint generated always as identity primary key,
    category_id bigint not null,
    category_name text not null,

    category_name_norm text,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_category_category_id unique (category_id)
);

create index idx_dim_category_name
    on dw.dim_category(category_name);


-- =========================================================
-- 3. DIMENSION: APP TYPE
-- =========================================================
-- We allow one technical "Unknown" row during ETL for missing app_type_id.

create table dw.dim_app_type (
    app_type_key bigint generated always as identity primary key,
    app_type_id bigint,
    app_type_name text not null,

    app_type_name_norm text,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_app_type_app_type_id unique (app_type_id),
    constraint uq_dim_app_type_name unique (app_type_name)
);

create index idx_dim_app_type_name
    on dw.dim_app_type(app_type_name);


-- =========================================================
-- 4. DIMENSION: CONTENT RATING
-- =========================================================

create table dw.dim_content_rating (
    content_rating_key bigint generated always as identity primary key,
    content_rating_id bigint not null,
    content_rating_name text not null,

    content_rating_name_norm text,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_content_rating_id unique (content_rating_id)
);

create index idx_dim_content_rating_name
    on dw.dim_content_rating(content_rating_name);


-- =========================================================
-- 5. DIMENSION: LAST UPDATED DATE
-- =========================================================
-- full_date is the actual day-level key.
-- day is day-of-month, not a hierarchy determinant by itself.

create table dw.dim_last_updated_date (
    last_updated_date_key bigint generated always as identity primary key,
    full_date date not null,

    day smallint not null,
    month smallint not null,
    quarter smallint not null,
    year integer not null,

    month_name text not null,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_last_updated_date_full_date unique (full_date),
    constraint chk_dim_date_day check (day between 1 and 31),
    constraint chk_dim_date_month check (month between 1 and 12),
    constraint chk_dim_date_quarter check (quarter between 1 and 4),
    constraint chk_dim_date_year check (year >= 1900)
);

create index idx_dim_last_updated_date_year_month
    on dw.dim_last_updated_date(year, month);

create index idx_dim_last_updated_date_full_date
    on dw.dim_last_updated_date(full_date);


-- =========================================================
-- 6. DIMENSION: GENRE
-- =========================================================

create table dw.dim_genre (
    genre_key bigint generated always as identity primary key,
    genre_id bigint not null,
    genre_name text not null,

    genre_name_norm text,

    inserted_at timestamptz not null default now(),

    constraint uq_dim_genre_genre_id unique (genre_id)
);

create index idx_dim_genre_name
    on dw.dim_genre(genre_name);


-- =========================================================
-- 7. FACT: APP SNAPSHOT
-- =========================================================
-- Measures:
--   rating
--   reviews_count
--   installs_count
--   price_usd
--   size_bytes
--
-- DQ flags are included as Phase 2 metadata so that BI users can filter
-- or explain missing values. They do not change the conceptual grain.

create table dw.fact_app_snapshot (
    app_snapshot_key bigint generated always as identity primary key,

    -- Source lineage
    snapshot_id bigint not null,
    raw_id bigint,

    -- Foreign keys
    app_key bigint not null,
    category_key bigint not null,
    app_type_key bigint not null,
    content_rating_key bigint not null,
    last_updated_date_key bigint not null,

    -- Measures
    rating numeric(3, 2),
    reviews_count bigint,
    installs_count bigint,
    price_usd numeric(10, 2),
    size_bytes bigint,

    -- Phase 2 DQ / cleaning metadata
    rating_missing_flag boolean not null default false,
    size_missing_flag boolean not null default false,
    size_varies_with_device_flag boolean not null default false,
    app_type_missing_flag boolean not null default false,
    current_version_missing_flag boolean not null default false,
    android_version_missing_flag boolean not null default false,
    multiple_genre_flag boolean not null default false,
    dq_status text not null default 'OK',

    inserted_at timestamptz not null default now(),

    constraint uq_fact_app_snapshot_snapshot_id unique (snapshot_id),

    constraint fk_fact_app_snapshot_app
        foreign key (app_key)
        references dw.dim_app(app_key),

    constraint fk_fact_app_snapshot_category
        foreign key (category_key)
        references dw.dim_category(category_key),

    constraint fk_fact_app_snapshot_app_type
        foreign key (app_type_key)
        references dw.dim_app_type(app_type_key),

    constraint fk_fact_app_snapshot_content_rating
        foreign key (content_rating_key)
        references dw.dim_content_rating(content_rating_key),

    constraint fk_fact_app_snapshot_last_updated_date
        foreign key (last_updated_date_key)
        references dw.dim_last_updated_date(last_updated_date_key),

    constraint chk_fact_rating
        check (rating is null or (rating >= 0 and rating <= 5)),

    constraint chk_fact_reviews_count
        check (reviews_count is null or reviews_count >= 0),

    constraint chk_fact_installs_count
        check (installs_count is null or installs_count >= 0),

    constraint chk_fact_price_usd
        check (price_usd is null or price_usd >= 0),

    constraint chk_fact_size_bytes
        check (size_bytes is null or size_bytes >= 0),

    constraint chk_fact_dq_status
        check (dq_status in ('OK', 'FLAGGED_OK', 'ERROR_REVIEW'))
);

create index idx_fact_app_snapshot_app
    on dw.fact_app_snapshot(app_key);

create index idx_fact_app_snapshot_category
    on dw.fact_app_snapshot(category_key);

create index idx_fact_app_snapshot_app_type
    on dw.fact_app_snapshot(app_type_key);

create index idx_fact_app_snapshot_content_rating
    on dw.fact_app_snapshot(content_rating_key);

create index idx_fact_app_snapshot_last_updated_date
    on dw.fact_app_snapshot(last_updated_date_key);

create index idx_fact_app_snapshot_dq_status
    on dw.fact_app_snapshot(dq_status);


-- =========================================================
-- 8. BRIDGE: APP SNAPSHOT - GENRE
-- =========================================================
-- This table implements the many-to-many relationship between
-- app snapshots and genres.
--
-- weight protects additive/snapshot-based measures from double counting
-- during Genre analyses:
--   snapshot with 1 genre  -> weight = 1.0
--   snapshot with 2 genres -> weight = 0.5 per genre

create table dw.bridge_app_snapshot_genre (
    app_snapshot_key bigint not null,
    genre_key bigint not null,

    weight numeric(20, 12) not null,

    inserted_at timestamptz not null default now(),

    constraint pk_bridge_app_snapshot_genre
        primary key (app_snapshot_key, genre_key),

    constraint fk_bridge_app_snapshot
        foreign key (app_snapshot_key)
        references dw.fact_app_snapshot(app_snapshot_key)
        on delete cascade,

    constraint fk_bridge_genre
        foreign key (genre_key)
        references dw.dim_genre(genre_key),

    constraint chk_bridge_weight_positive
        check (weight > 0 and weight <= 1)
);

create index idx_bridge_app_snapshot_genre_snapshot
    on dw.bridge_app_snapshot_genre(app_snapshot_key);

create index idx_bridge_app_snapshot_genre_genre
    on dw.bridge_app_snapshot_genre(genre_key);


-- =========================================================
-- 9. ANALYSIS VIEWS
-- =========================================================
-- These views guide BI usage and reduce the risk of incorrect
-- aggregation over the many-to-many Genre bridge.

create or replace view dw.v_fact_app_snapshot_enriched as
select
    f.app_snapshot_key,
    f.snapshot_id,
    f.raw_id,

    da.app_name,
    dc.category_name,
    dat.app_type_name,
    dcr.content_rating_name,
    dd.full_date as last_updated_date,
    dd.day,
    dd.month,
    dd.quarter,
    dd.year,

    f.rating,
    f.reviews_count,
    f.installs_count,
    f.price_usd,
    f.size_bytes,

    f.rating_missing_flag,
    f.size_missing_flag,
    f.size_varies_with_device_flag,
    f.app_type_missing_flag,
    f.current_version_missing_flag,
    f.android_version_missing_flag,
    f.multiple_genre_flag,
    f.dq_status

from dw.fact_app_snapshot f
join dw.dim_app da
    on f.app_key = da.app_key
join dw.dim_category dc
    on f.category_key = dc.category_key
join dw.dim_app_type dat
    on f.app_type_key = dat.app_type_key
join dw.dim_content_rating dcr
    on f.content_rating_key = dcr.content_rating_key
join dw.dim_last_updated_date dd
    on f.last_updated_date_key = dd.last_updated_date_key;


create or replace view dw.v_genre_fractional_analysis as
select
    f.app_snapshot_key,
    f.snapshot_id,

    g.genre_name,
    b.weight,

    f.rating,
    f.reviews_count,
    f.installs_count,
    f.price_usd,
    f.size_bytes,

    -- Weighted additive/snapshot-based measures for safe Genre analysis
    f.reviews_count * b.weight as weighted_reviews_count,
    f.installs_count * b.weight as weighted_installs_count,
    b.weight as weighted_snapshot_count,

    f.rating_missing_flag,
    f.size_missing_flag,
    f.size_varies_with_device_flag,
    f.multiple_genre_flag,
    f.dq_status

from dw.fact_app_snapshot f
join dw.bridge_app_snapshot_genre b
    on f.app_snapshot_key = b.app_snapshot_key
join dw.dim_genre g
    on b.genre_key = g.genre_key;


create or replace view dw.v_genre_membership_analysis as
select
    g.genre_name,
    count(distinct f.app_snapshot_key) as snapshot_membership_count,
    avg(f.rating) as avg_rating,
    avg(f.price_usd) as avg_price_usd,
    avg(f.size_bytes) as avg_size_bytes
from dw.fact_app_snapshot f
join dw.bridge_app_snapshot_genre b
    on f.app_snapshot_key = b.app_snapshot_key
join dw.dim_genre g
    on b.genre_key = g.genre_key
group by g.genre_name;


create or replace view dw.v_bridge_weight_check as
select
    app_snapshot_key,
    count(*) as genre_count,
    sum(weight) as weight_sum,
    abs(sum(weight) - 1.0) as weight_error
from dw.bridge_app_snapshot_genre
group by app_snapshot_key
having abs(sum(weight) - 1.0) > 0.000001;


commit;