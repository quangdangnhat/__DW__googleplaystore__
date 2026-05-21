-- =========================================================
-- FILE: 08_dw_etl.sql
-- PROJECT: Google Play Store Data Warehouse
-- PHASE: Phase 2 - ETL from Clean/Reconciled Layer to DW
-- PURPOSE:
--   Populate the DW star schema from the clean layer.
--
-- RUN AFTER:
--   07_dw_star_schema.sql
-- =========================================================

begin;

-- =========================================================
-- 0. RESET DW DATA ONLY
-- =========================================================

truncate table
    dw.bridge_app_snapshot_genre,
    dw.fact_app_snapshot,
    dw.dim_app,
    dw.dim_category,
    dw.dim_app_type,
    dw.dim_content_rating,
    dw.dim_last_updated_date,
    dw.dim_genre
restart identity cascade;


-- =========================================================
-- 1. LOAD DIM_APP
-- =========================================================

insert into dw.dim_app (
    app_id,
    app_name,
    app_name_norm
)
select
    app_id,
    app_name,
    app_name_norm
from reconciled.app
order by app_id;


-- =========================================================
-- 2. LOAD DIM_CATEGORY
-- =========================================================

insert into dw.dim_category (
    category_id,
    category_name,
    category_name_norm
)
select
    category_id,
    category_name,
    category_name_norm
from reconciled.category
order by category_id;


-- =========================================================
-- 3. LOAD DIM_APP_TYPE
-- =========================================================
-- Includes one technical Unknown row because one source snapshot has
-- missing Type. This avoids NULL foreign keys in the fact table.

insert into dw.dim_app_type (
    app_type_id,
    app_type_name,
    app_type_name_norm
)
select
    app_type_id,
    app_type_name,
    app_type_name_norm
from reconciled.app_type
order by app_type_id;

insert into dw.dim_app_type (
    app_type_id,
    app_type_name,
    app_type_name_norm
)
values (
    null,
    'Unknown',
    'unknown'
);


-- =========================================================
-- 4. LOAD DIM_CONTENT_RATING
-- =========================================================

insert into dw.dim_content_rating (
    content_rating_id,
    content_rating_name,
    content_rating_name_norm
)
select
    content_rating_id,
    content_rating_name,
    content_rating_name_norm
from reconciled.content_rating
order by content_rating_id;


-- =========================================================
-- 5. LOAD DIM_GENRE
-- =========================================================

insert into dw.dim_genre (
    genre_id,
    genre_name,
    genre_name_norm
)
select
    genre_id,
    genre_name,
    genre_name_norm
from reconciled.genre
order by genre_id;


-- =========================================================
-- 6. LOAD DIM_LAST_UPDATED_DATE
-- =========================================================
-- full_date is the real day-level key.
-- day is day-of-month.

insert into dw.dim_last_updated_date (
    full_date,
    day,
    month,
    quarter,
    year,
    month_name
)
select distinct
    c.last_updated_date as full_date,
    extract(day from c.last_updated_date)::smallint as day,
    extract(month from c.last_updated_date)::smallint as month,
    extract(quarter from c.last_updated_date)::smallint as quarter,
    extract(year from c.last_updated_date)::integer as year,
    trim(to_char(c.last_updated_date, 'Month')) as month_name
from clean.app_snapshot_clean c
where c.last_updated_date is not null
order by c.last_updated_date;


-- =========================================================
-- 7. LOAD FACT_APP_SNAPSHOT
-- =========================================================

insert into dw.fact_app_snapshot (
    snapshot_id,
    raw_id,

    app_key,
    category_key,
    app_type_key,
    content_rating_key,
    last_updated_date_key,

    rating,
    reviews_count,
    installs_count,
    price_usd,
    size_bytes,

    rating_missing_flag,
    size_missing_flag,
    size_varies_with_device_flag,
    app_type_missing_flag,
    current_version_missing_flag,
    android_version_missing_flag,
    multiple_genre_flag,
    dq_status
)
select
    c.snapshot_id,
    c.raw_id,

    da.app_key,
    dc.category_key,
    coalesce(dat.app_type_key, dat_unknown.app_type_key) as app_type_key,
    dcr.content_rating_key,
    dd.last_updated_date_key,

    c.rating,
    c.reviews_count,
    c.installs_count,
    c.price_usd,
    c.size_bytes,

    c.rating_missing_flag,
    c.size_missing_flag,
    c.size_varies_with_device_flag,
    c.app_type_missing_flag,
    c.current_version_missing_flag,
    c.android_version_missing_flag,
    c.multiple_genre_flag,
    c.dq_status

from clean.app_snapshot_clean c

join dw.dim_app da
    on c.app_id = da.app_id

join dw.dim_category dc
    on c.category_id = dc.category_id

left join dw.dim_app_type dat
    on c.app_type_id = dat.app_type_id

join dw.dim_app_type dat_unknown
    on dat_unknown.app_type_name_norm = 'unknown'

join dw.dim_content_rating dcr
    on c.content_rating_id = dcr.content_rating_id

join dw.dim_last_updated_date dd
    on c.last_updated_date = dd.full_date

order by c.snapshot_id;


-- =========================================================
-- 8. LOAD BRIDGE_APP_SNAPSHOT_GENRE
-- =========================================================
-- The weight is already computed in clean.app_snapshot_genre_clean.
-- It prevents double counting during Genre analysis.

insert into dw.bridge_app_snapshot_genre (
    app_snapshot_key,
    genre_key,
    weight
)
select
    f.app_snapshot_key,
    dg.genre_key,
    cb.weight
from clean.app_snapshot_genre_clean cb
join dw.fact_app_snapshot f
    on cb.snapshot_id = f.snapshot_id
join dw.dim_genre dg
    on cb.genre_id = dg.genre_id
order by f.app_snapshot_key, dg.genre_key;


-- =========================================================
-- 9. DW LOAD SUMMARY VIEW
-- =========================================================

create or replace view dw.v_dw_load_summary as
select 'dim_app_rows' as metric, count(*)::text as value
from dw.dim_app

union all
select 'dim_category_rows', count(*)::text
from dw.dim_category

union all
select 'dim_app_type_rows', count(*)::text
from dw.dim_app_type

union all
select 'dim_content_rating_rows', count(*)::text
from dw.dim_content_rating

union all
select 'dim_last_updated_date_rows', count(*)::text
from dw.dim_last_updated_date

union all
select 'dim_genre_rows', count(*)::text
from dw.dim_genre

union all
select 'fact_app_snapshot_rows', count(*)::text
from dw.fact_app_snapshot

union all
select 'bridge_app_snapshot_genre_rows', count(*)::text
from dw.bridge_app_snapshot_genre

union all
select 'unknown_app_type_fact_rows', count(*)::text
from dw.fact_app_snapshot f
join dw.dim_app_type dat
    on f.app_type_key = dat.app_type_key
where dat.app_type_name_norm = 'unknown'

union all
select 'fact_rating_missing_flag_rows', count(*)::text
from dw.fact_app_snapshot
where rating_missing_flag

union all
select 'fact_size_missing_flag_rows', count(*)::text
from dw.fact_app_snapshot
where size_missing_flag

union all
select 'fact_multiple_genre_flag_rows', count(*)::text
from dw.fact_app_snapshot
where multiple_genre_flag;


-- =========================================================
-- 10. DW INTEGRITY CHECK VIEW
-- =========================================================

create or replace view dw.v_dw_integrity_checks as
select
    'fact_rows_match_clean_rows' as check_name,
    (select count(*) from clean.app_snapshot_clean)::numeric as expected_value,
    (select count(*) from dw.fact_app_snapshot)::numeric as actual_value,
    case
        when (select count(*) from clean.app_snapshot_clean)
           = (select count(*) from dw.fact_app_snapshot)
        then 'PASS'
        else 'FAIL'
    end as status

union all

select
    'bridge_rows_match_clean_bridge_rows',
    (select count(*) from clean.app_snapshot_genre_clean)::numeric,
    (select count(*) from dw.bridge_app_snapshot_genre)::numeric,
    case
        when (select count(*) from clean.app_snapshot_genre_clean)
           = (select count(*) from dw.bridge_app_snapshot_genre)
        then 'PASS'
        else 'FAIL'
    end

union all

select
    'genre_bridge_weight_errors',
    0::numeric,
    (select count(*) from dw.v_bridge_weight_check)::numeric,
    case
        when (select count(*) from dw.v_bridge_weight_check) = 0
        then 'PASS'
        else 'FAIL'
    end

union all

select
    'fact_duplicate_snapshot_id',
    0::numeric,
    (
        select count(*)::numeric
        from (
            select snapshot_id
            from dw.fact_app_snapshot
            group by snapshot_id
            having count(*) > 1
        ) d
    ),
    case
        when (
            select count(*)
            from (
                select snapshot_id
                from dw.fact_app_snapshot
                group by snapshot_id
                having count(*) > 1
            ) d
        ) = 0
        then 'PASS'
        else 'FAIL'
    end

union all

select
    'fact_error_review_rows',
    0::numeric,
    (select count(*)::numeric from dw.fact_app_snapshot where dq_status = 'ERROR_REVIEW'),
    case
        when (select count(*) from dw.fact_app_snapshot where dq_status = 'ERROR_REVIEW') = 0
        then 'PASS'
        else 'FAIL'
    end;


-- =========================================================
-- 11. OPTIONAL AGGREGATION CHECKS FOR GENRE
-- =========================================================
-- This view demonstrates the correct weighted semantic for Genre.
-- It should be used instead of directly summing measures after a Genre join.

create or replace view dw.v_genre_weighted_kpis as
select
    genre_name,

    sum(weighted_snapshot_count) as weighted_snapshot_count,
    sum(weighted_reviews_count) as weighted_reviews_count,
    sum(weighted_installs_count) as weighted_installs_count,

    avg(rating) filter (where rating is not null) as avg_rating_unweighted,

    case
        when sum(weight) filter (where rating is not null) = 0 then null
        else
            sum(rating * weight) filter (where rating is not null)
            /
            sum(weight) filter (where rating is not null)
    end as avg_rating_weighted

from dw.v_genre_fractional_analysis
group by genre_name;


commit;