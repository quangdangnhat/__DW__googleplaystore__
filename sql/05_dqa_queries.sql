-- =========================================================
-- FILE: 05_dqa_queries.sql
-- PROJECT: Google Play Store Data Warehouse
-- PHASE: Phase 2 - Baseline Data Quality Assessment
-- PURPOSE:
--   Assess data quality on the reconciled database BEFORE cleaning.
--   This file does not modify source/reconciled data.
--
-- RUN AFTER:
--   01_reconciled_schema.sql
--   CSV import into raw.googleplaystore_import
--   02_domain_load.sql
--   03_app_snapshot_etl.sql
--   04_genre_etl.sql
-- =========================================================

create schema if not exists dq;

-- =========================================================
-- 1. RECONCILIATION COUNTS
-- =========================================================
-- This view verifies that raw data has been transformed into the
-- reconciled layer as expected.

create or replace view dq.v_reconciliation_counts as
select 'raw_rows' as metric, count(*)::text as value
from raw.googleplaystore_import

union all
select 'reconciled_app_rows', count(*)::text
from reconciled.app

union all
select 'reconciled_category_rows', count(*)::text
from reconciled.category

union all
select 'reconciled_app_type_rows', count(*)::text
from reconciled.app_type

union all
select 'reconciled_content_rating_rows', count(*)::text
from reconciled.content_rating

union all
select 'reconciled_app_snapshot_rows', count(*)::text
from reconciled.app_snapshot

union all
select 'reconciled_genre_rows', count(*)::text
from reconciled.genre

union all
select 'reconciled_app_snapshot_genre_rows', count(*)::text
from reconciled.app_snapshot_genre

union all
select 'raw_rows_not_loaded_to_snapshot', count(*)::text
from raw.googleplaystore_import r
left join reconciled.app_snapshot s
    on s.raw_id = r.raw_id
where s.raw_id is null;


-- =========================================================
-- 2. ENRICHED SNAPSHOT VIEW FOR DQA
-- =========================================================
-- This view joins the fact-like reconciled snapshot table with
-- descriptive domain tables. It is useful for readable DQA queries.

create or replace view dq.v_app_snapshot_enriched as
select
    s.snapshot_id,
    s.raw_id,

    s.app_id,
    a.app_name,
    a.app_name_norm,

    s.category_id,
    c.category_name,
    c.category_name_norm,

    s.app_type_id,
    atp.app_type_name,
    atp.app_type_name_norm,

    s.content_rating_id,
    cr.content_rating_name,
    cr.content_rating_name_norm,

    s.rating,
    s.reviews_count,
    s.size_bytes,
    s.installs_count,
    s.price_usd,
    s.last_updated_date,
    s.current_version,
    s.android_version_text,

    r."App" as raw_app,
    r."Category" as raw_category,
    r."Rating" as raw_rating,
    r."Reviews" as raw_reviews,
    r."Size" as raw_size,
    r."Installs" as raw_installs,
    r."Type" as raw_type,
    r."Price" as raw_price,
    r."Content Rating" as raw_content_rating,
    r."Genres" as raw_genres,
    r."Last Updated" as raw_last_updated,
    r."Current Ver" as raw_current_version,
    r."Android Ver" as raw_android_version

from reconciled.app_snapshot s
left join reconciled.app a
    on s.app_id = a.app_id
left join reconciled.category c
    on s.category_id = c.category_id
left join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id
left join reconciled.content_rating cr
    on s.content_rating_id = cr.content_rating_id
left join raw.googleplaystore_import r
    on s.raw_id = r.raw_id;


-- =========================================================
-- 3. BASELINE DQA SCORECARD
-- =========================================================
-- Dimensions covered:
--   Completeness
--   Uniqueness
--   Validity
--   Consistency
--   Timeliness
--   Accuracy
--
-- Accuracy is included as "not fully scored" because external ground truth
-- is not available. This is correct and honest for this dataset.

create or replace view dq.v_dqa_baseline_scorecard as
with metrics as (

    -- =====================================================
    -- COMPLETENESS
    -- =====================================================

    select
        'Completeness' as dimension,
        'core_required_fields_missing' as metric,
        'reconciled.app_snapshot' as checked_object,
        count(*)::numeric as total_checked,
        count(*) filter (
            where app_id is null
               or category_id is null
               or content_rating_id is null
               or reviews_count is null
               or installs_count is null
               or price_usd is null
               or last_updated_date is null
        )::numeric as issue_count,
        'Core fields should be present for each loaded app snapshot. Rating and size are excluded because missing values are analytically meaningful.' as details,
        'Investigate rows with missing core fields before loading the DW fact table.' as recommendation
    from dq.v_app_snapshot_enriched

    union all

    select
        'Completeness',
        'rating_missing',
        'reconciled.app_snapshot.rating',
        count(*)::numeric,
        count(*) filter (where rating is null)::numeric,
        'Rating can be missing in the source dataset. It should not be blindly imputed because it is an analytical measure.',
        'Preserve NULL rating and create rating_missing_flag during cleaning.'
    from dq.v_app_snapshot_enriched

    union all

    select
        'Completeness',
        'size_missing_or_varies_with_device',
        'reconciled.app_snapshot.size_bytes',
        count(*)::numeric,
        count(*) filter (where size_bytes is null)::numeric,
        'Size is NULL when the raw value is missing or equal to "Varies with device". This is meaningful source information.',
        'Preserve NULL size and create size_missing_or_varies_flag during cleaning.'
    from dq.v_app_snapshot_enriched

    union all

    select
        'Completeness',
        'app_type_missing',
        'reconciled.app_snapshot.app_type_id',
        count(*)::numeric,
        count(*) filter (where app_type_id is null)::numeric,
        'App type should usually be Free or Paid. Missing type should be flagged instead of guessed.',
        'Create app_type_missing_flag. Do not infer Free/Paid unless a documented business rule is approved.'
    from dq.v_app_snapshot_enriched

    union all

    select
        'Completeness',
        'current_version_missing',
        'reconciled.app_snapshot.current_version',
        count(*)::numeric,
        count(*) filter (
            where current_version is null
               or trim(current_version) = ''
               or lower(trim(current_version)) in ('nan', 'null')
        )::numeric,
        'Current version is descriptive metadata and may be missing for some apps.',
        'Preserve missing value and optionally flag it for metadata-quality analysis.'
    from dq.v_app_snapshot_enriched

    union all

    select
        'Completeness',
        'android_version_missing',
        'reconciled.app_snapshot.android_version_text',
        count(*)::numeric,
        count(*) filter (
            where android_version_text is null
               or trim(android_version_text) = ''
               or lower(trim(android_version_text)) in ('nan', 'null')
        )::numeric,
        'Android version is descriptive metadata and may be missing or vary across devices.',
        'Preserve missing value and optionally flag it for metadata-quality analysis.'
    from dq.v_app_snapshot_enriched


    -- =====================================================
    -- UNIQUENESS
    -- =====================================================

    union all

    select
        'Uniqueness',
        'duplicate_raw_id_in_app_snapshot',
        'reconciled.app_snapshot.raw_id',
        count(*)::numeric,
        (
            select coalesce(sum(dup_count - 1), 0)::numeric
            from (
                select raw_id, count(*) as dup_count
                from reconciled.app_snapshot
                group by raw_id
                having count(*) > 1
            ) d
        ) as issue_count,
        'Each raw row should generate at most one reconciled app snapshot.',
        'If duplicates exist, inspect ETL joins and source row identifiers.'
    from reconciled.app_snapshot

    union all

    select
        'Uniqueness',
        'duplicate_app_name_norm',
        'reconciled.app.app_name_norm',
        count(*)::numeric,
        (
            select coalesce(sum(dup_count - 1), 0)::numeric
            from (
                select app_name_norm, count(*) as dup_count
                from reconciled.app
                group by app_name_norm
                having count(*) > 1
            ) d
        ) as issue_count,
        'Normalized app names should be unique in the app master table.',
        'If duplicates exist, improve normalization rules.'
    from reconciled.app

    union all

    select
        'Uniqueness',
        'duplicate_snapshot_genre_pair',
        'reconciled.app_snapshot_genre(snapshot_id, genre_id)',
        count(*)::numeric,
        (
            select coalesce(sum(dup_count - 1), 0)::numeric
            from (
                select snapshot_id, genre_id, count(*) as dup_count
                from reconciled.app_snapshot_genre
                group by snapshot_id, genre_id
                having count(*) > 1
            ) d
        ) as issue_count,
        'Each snapshot-genre pair should appear only once.',
        'If duplicates exist, deduplicate the bridge table before DW loading.'
    from reconciled.app_snapshot_genre


    -- =====================================================
    -- VALIDITY
    -- =====================================================

    union all

    select
        'Validity',
        'rating_out_of_range',
        'reconciled.app_snapshot.rating',
        count(*)::numeric,
        count(*) filter (where rating is not null and (rating < 0 or rating > 5))::numeric,
        'Rating must be between 0 and 5.',
        'Invalid ratings should be set to NULL and logged during cleaning.'
    from reconciled.app_snapshot

    union all

    select
        'Validity',
        'negative_reviews_count',
        'reconciled.app_snapshot.reviews_count',
        count(*)::numeric,
        count(*) filter (where reviews_count < 0)::numeric,
        'Review count cannot be negative.',
        'Invalid review counts should be investigated and nullified if needed.'
    from reconciled.app_snapshot

    union all

    select
        'Validity',
        'negative_installs_count',
        'reconciled.app_snapshot.installs_count',
        count(*)::numeric,
        count(*) filter (where installs_count < 0)::numeric,
        'Install count cannot be negative.',
        'Invalid install counts should be investigated and nullified if needed.'
    from reconciled.app_snapshot

    union all

    select
        'Validity',
        'negative_price_usd',
        'reconciled.app_snapshot.price_usd',
        count(*)::numeric,
        count(*) filter (where price_usd < 0)::numeric,
        'Price cannot be negative.',
        'Invalid prices should be set to NULL or corrected from source if possible.'
    from reconciled.app_snapshot

    union all

    select
        'Validity',
        'negative_size_bytes',
        'reconciled.app_snapshot.size_bytes',
        count(*)::numeric,
        count(*) filter (where size_bytes < 0)::numeric,
        'Application size in bytes cannot be negative.',
        'Invalid sizes should be set to NULL and logged.'
    from reconciled.app_snapshot

    union all

    select
        'Validity',
        'invalid_domain_values_after_load',
        'reconciled domain tables',
        (
            (select count(*) from reconciled.category)
          + (select count(*) from reconciled.app_type)
          + (select count(*) from reconciled.content_rating)
        )::numeric,
        (
            (select count(*) from reconciled.category
             where category_name_norm in ('1.9', 'nan', 'null', '0', ''))
          + (select count(*) from reconciled.app_type
             where app_type_name_norm not in ('free', 'paid'))
          + (select count(*) from reconciled.content_rating
             where content_rating_name_norm in ('nan', 'null', '0', ''))
        )::numeric,
        'Domain tables should not contain shifted row values or textual null markers.',
        'If issues exist, fix domain-load filters and rerun the reconciled load.'
    

    -- =====================================================
    -- CONSISTENCY
    -- =====================================================

    union all

    select
        'Consistency',
        'type_price_conflict',
        'reconciled.app_snapshot + reconciled.app_type',
        count(*)::numeric,
        count(*) filter (
            where
                (app_type_name_norm = 'free' and price_usd > 0)
                or
                (app_type_name_norm = 'paid' and coalesce(price_usd, 0) = 0)
        )::numeric,
        'Free apps should have price 0. Paid apps should usually have price greater than 0.',
        'Rows with Type/Price conflicts should be flagged and inspected.'
    from dq.v_app_snapshot_enriched

    union all

    select
        'Consistency',
        'snapshot_without_genre',
        'reconciled.app_snapshot vs reconciled.app_snapshot_genre',
        count(*)::numeric,
        count(*) filter (where genre_count = 0)::numeric,
        'Each snapshot should have at least one genre according to the source dataset.',
        'If missing, inspect raw Genres and bridge ETL.'
    from (
        select
            s.snapshot_id,
            count(sg.genre_id) as genre_count
        from reconciled.app_snapshot s
        left join reconciled.app_snapshot_genre sg
            on s.snapshot_id = sg.snapshot_id
        group by s.snapshot_id
    ) x

    union all

    select
        'Consistency',
        'orphan_snapshot_genre_rows',
        'reconciled.app_snapshot_genre foreign-key consistency',
        count(*)::numeric,
        count(*) filter (
            where s.snapshot_id is null
               or g.genre_id is null
        )::numeric,
        'Bridge rows must reference existing snapshots and existing genres.',
        'Orphan bridge rows must be removed before DW loading.'
    from reconciled.app_snapshot_genre sg
    left join reconciled.app_snapshot s
        on sg.snapshot_id = s.snapshot_id
    left join reconciled.genre g
        on sg.genre_id = g.genre_id


    -- =====================================================
    -- TIMELINESS
    -- =====================================================

    union all

    select
        'Timeliness',
        'future_last_updated_date',
        'reconciled.app_snapshot.last_updated_date',
        count(*)::numeric,
        count(*) filter (where last_updated_date > current_date)::numeric,
        'Last updated date should not be in the future.',
        'Future dates should be corrected if source evidence exists, otherwise nullified and logged.'
    from reconciled.app_snapshot

    union all

    select
        'Timeliness',
        'last_updated_date_missing',
        'reconciled.app_snapshot.last_updated_date',
        count(*)::numeric,
        count(*) filter (where last_updated_date is null)::numeric,
        'Last updated date supports the time dimension and should be present.',
        'Missing update dates must be investigated before DW loading.'
    from reconciled.app_snapshot


    -- =====================================================
    -- ACCURACY
    -- =====================================================
    -- Accuracy normally requires external reference truth.
    -- We report it honestly as not fully scored.

    union all

    select
        'Accuracy',
        'external_ground_truth_not_available',
        'Google Play Store source values',
        null::numeric as total_checked,
        null::numeric as issue_count,
        'Accuracy cannot be fully verified without an external trusted source such as current Google Play Store metadata.',
        'Document this limitation. Use validity, consistency, and outlier checks as internal proxies only.'
)
select
    dimension,
    metric,
    checked_object,
    total_checked,
    issue_count,
    case
        when total_checked is null or issue_count is null then null
        when total_checked = 0 then null
        else round(1 - (issue_count / total_checked), 4)
    end as score,
    case
        when total_checked is null or issue_count is null then 'INFO'
        when total_checked = 0 then 'INFO'
        when round(1 - (issue_count / total_checked), 4) >= 0.95 then 'GREEN'
        when round(1 - (issue_count / total_checked), 4) >= 0.80 then 'YELLOW'
        else 'RED'
    end as severity,
    details,
    recommendation
from metrics;


-- =========================================================
-- 4. ISSUE DETAIL VIEWS
-- =========================================================
-- These views identify rows that may need cleaning or flagging.

create or replace view dq.v_issue_missing_rating as
select *
from dq.v_app_snapshot_enriched
where rating is null;


create or replace view dq.v_issue_missing_size as
select *
from dq.v_app_snapshot_enriched
where size_bytes is null;


create or replace view dq.v_issue_missing_app_type as
select *
from dq.v_app_snapshot_enriched
where app_type_id is null;


create or replace view dq.v_issue_type_price_conflict as
select *
from dq.v_app_snapshot_enriched
where
    (app_type_name_norm = 'free' and price_usd > 0)
    or
    (app_type_name_norm = 'paid' and coalesce(price_usd, 0) = 0);


create or replace view dq.v_issue_invalid_measures as
select *
from dq.v_app_snapshot_enriched
where
    (rating is not null and (rating < 0 or rating > 5))
    or reviews_count < 0
    or installs_count < 0
    or price_usd < 0
    or size_bytes < 0;


create or replace view dq.v_issue_raw_rows_not_loaded as
select
    r.*
from raw.googleplaystore_import r
left join reconciled.app_snapshot s
    on s.raw_id = r.raw_id
where s.raw_id is null;


-- =========================================================
-- 5. GENRE MANY-TO-MANY ANALYSIS SUPPORT
-- =========================================================
-- This helps us understand the risk of double counting in analyses
-- involving Genre.

create or replace view dq.v_genre_distribution_per_snapshot as
select
    genre_count,
    count(*) as snapshot_count
from (
    select
        s.snapshot_id,
        count(sg.genre_id) as genre_count
    from reconciled.app_snapshot s
    left join reconciled.app_snapshot_genre sg
        on s.snapshot_id = sg.snapshot_id
    group by s.snapshot_id
) x
group by genre_count
order by genre_count;


create or replace view dq.v_snapshot_genre_weight_preview as
select
    sg.snapshot_id,
    sg.genre_id,
    g.genre_name,
    count(*) over (partition by sg.snapshot_id) as genre_count_for_snapshot,
    round(
        1.0 / nullif(count(*) over (partition by sg.snapshot_id), 0),
        6
    ) as future_dw_bridge_weight
from reconciled.app_snapshot_genre sg
join reconciled.genre g
    on sg.genre_id = g.genre_id;


create or replace view dq.v_snapshot_genre_weight_check as
select
    snapshot_id,
    count(*) as genre_count,
    sum(future_dw_bridge_weight) as weight_sum
from dq.v_snapshot_genre_weight_preview
group by snapshot_id
having abs(sum(future_dw_bridge_weight) - 1.0) > 0.0001;


-- =========================================================
-- 6. OUTPUTS TO SCREEN
-- =========================================================
-- Supabase SQL Editor usually displays the last SELECT result.
-- Run the SELECT statements below one by one if you want screenshots.

select *
from dq.v_reconciliation_counts;


select *
from dq.v_dqa_baseline_scorecard
order by
    case dimension
        when 'Completeness' then 1
        when 'Uniqueness' then 2
        when 'Validity' then 3
        when 'Consistency' then 4
        when 'Timeliness' then 5
        when 'Accuracy' then 6
        else 99
    end,
    metric;


select *
from dq.v_genre_distribution_per_snapshot;


select *
from dq.v_snapshot_genre_weight_check;