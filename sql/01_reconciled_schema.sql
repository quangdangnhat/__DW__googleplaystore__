-- =========================================================
-- 01_reconciled_schema.sql
-- Project: Google Play Store
-- Purpose:
--   1) Create raw schema for original CSV landing
--   2) Create reconciled schema
--   3) Create reconciled domain and core tables
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 0) RESET FOR CLEAN RERUN
-- ---------------------------------------------------------
drop schema if exists reconciled cascade;
drop schema if exists raw cascade;

-- ---------------------------------------------------------
-- 1) CREATE SCHEMAS
-- ---------------------------------------------------------
create schema raw;
create schema reconciled;

comment on schema raw is
'Raw landing area for the original source CSV, kept as close as possible to the source format.';

comment on schema reconciled is
'Reconciled layer for standardized, typed, and cleaned data before DW loading.';

-- =========================================================
-- 2) RAW LAYER
--    IMPORTANT:
--    Column names match the CSV headers exactly so that
--    Supabase CSV import works without header mismatch.
-- =========================================================
create table raw.googleplaystore_import (
    raw_id               bigint generated always as identity primary key,

    "App"                text,
    "Category"           text,
    "Rating"             text,
    "Reviews"            text,
    "Size"               text,
    "Installs"           text,
    "Type"               text,
    "Price"              text,
    "Content Rating"     text,
    "Genres"             text,
    "Last Updated"       text,
    "Current Ver"        text,
    "Android Ver"        text,

    imported_at          timestamptz not null default now()
);

comment on table raw.googleplaystore_import is
'Landing table for the original Google Play Store CSV. Headers intentionally match the source file exactly.';

-- =========================================================
-- 3) RECONCILED DOMAIN TABLES
-- =========================================================

create table reconciled.category (
    category_id              bigint generated always as identity primary key,
    category_name            text not null,
    category_name_norm       text not null,
    created_at               timestamptz not null default now(),
    constraint uq_category_name_norm unique (category_name_norm)
);

comment on table reconciled.category is
'Normalized domain table for app categories.';

create table reconciled.app_type (
    app_type_id              bigint generated always as identity primary key,
    app_type_name            text not null,
    app_type_name_norm       text not null,
    created_at               timestamptz not null default now(),
    constraint uq_app_type_name_norm unique (app_type_name_norm)
);

comment on table reconciled.app_type is
'Normalized domain table for app monetization type such as Free and Paid.';

create table reconciled.content_rating (
    content_rating_id        bigint generated always as identity primary key,
    content_rating_name      text not null,
    content_rating_name_norm text not null,
    created_at               timestamptz not null default now(),
    constraint uq_content_rating_name_norm unique (content_rating_name_norm)
);

comment on table reconciled.content_rating is
'Normalized domain table for content ratings such as Everyone, Teen, Mature 17+.';

create table reconciled.genre (
    genre_id                 bigint generated always as identity primary key,
    genre_name               text not null,
    genre_name_norm          text not null,
    created_at               timestamptz not null default now(),
    constraint uq_genre_name_norm unique (genre_name_norm)
);

comment on table reconciled.genre is
'Normalized genre table extracted from the raw Genres column.';

-- =========================================================
-- 4) RECONCILED CORE TABLES
-- =========================================================

create table reconciled.app (
    app_id                   bigint generated always as identity primary key,
    app_name                 text not null,
    app_name_norm            text not null,
    created_at               timestamptz not null default now(),
    constraint uq_app_name_norm unique (app_name_norm)
);

comment on table reconciled.app is
'Master app entity deduplicated by normalized app name.';

create table reconciled.app_snapshot (
    snapshot_id              bigint generated always as identity primary key,

    raw_id                   bigint not null unique,
    app_id                   bigint not null,
    category_id              bigint,
    app_type_id              bigint,
    content_rating_id        bigint,

    rating                   numeric(3,2),
    reviews_count            bigint,
    size_bytes               bigint,
    installs_count           bigint,
    price_usd                numeric(10,2),
    last_updated_date        date,

    current_version          text,
    android_version_text     text,

    inserted_at              timestamptz not null default now(),

    constraint fk_snapshot_raw
        foreign key (raw_id)
        references raw.googleplaystore_import(raw_id),

    constraint fk_snapshot_app
        foreign key (app_id)
        references reconciled.app(app_id),

    constraint fk_snapshot_category
        foreign key (category_id)
        references reconciled.category(category_id),

    constraint fk_snapshot_app_type
        foreign key (app_type_id)
        references reconciled.app_type(app_type_id),

    constraint fk_snapshot_content_rating
        foreign key (content_rating_id)
        references reconciled.content_rating(content_rating_id),

    constraint ck_snapshot_rating_range
        check (rating is null or (rating >= 0 and rating <= 5)),

    constraint ck_snapshot_reviews_nonnegative
        check (reviews_count is null or reviews_count >= 0),

    constraint ck_snapshot_size_nonnegative
        check (size_bytes is null or size_bytes >= 0),

    constraint ck_snapshot_installs_nonnegative
        check (installs_count is null or installs_count >= 0),

    constraint ck_snapshot_price_nonnegative
        check (price_usd is null or price_usd >= 0)
);

comment on table reconciled.app_snapshot is
'Reconciled typed version of each raw CSV row. One raw row corresponds to one snapshot row.';

create table reconciled.app_snapshot_genre (
    snapshot_id              bigint not null,
    genre_id                 bigint not null,
    inserted_at              timestamptz not null default now(),

    constraint pk_app_snapshot_genre
        primary key (snapshot_id, genre_id),

    constraint fk_app_snapshot_genre_snapshot
        foreign key (snapshot_id)
        references reconciled.app_snapshot(snapshot_id)
        on delete cascade,

    constraint fk_app_snapshot_genre_genre
        foreign key (genre_id)
        references reconciled.genre(genre_id)
);

comment on table reconciled.app_snapshot_genre is
'Bridge table between app snapshots and genres.';

-- =========================================================
-- 5) HELPFUL INDEXES
-- =========================================================

create index idx_raw_googleplaystore_app 
    on raw.googleplaystore_import ("App");

create index idx_raw_googleplaystore_category
    on raw.googleplaystore_import ("Category");

create index idx_app_snapshot_app_id
    on reconciled.app_snapshot (app_id);

create index idx_app_snapshot_category_id
    on reconciled.app_snapshot (category_id);

create index idx_app_snapshot_app_type_id
    on reconciled.app_snapshot (app_type_id);

create index idx_app_snapshot_content_rating_id
    on reconciled.app_snapshot (content_rating_id);

create index idx_app_snapshot_last_updated_date
    on reconciled.app_snapshot (last_updated_date);

create index idx_app_snapshot_installs_count
    on reconciled.app_snapshot (installs_count);

commit;