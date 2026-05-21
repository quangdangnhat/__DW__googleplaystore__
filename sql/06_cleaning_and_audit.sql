-- =========================================================
-- FILE: 06_cleaning_and_audit.sql
-- PROJECT: Google Play Store Data Warehouse
-- PHASE: Phase 2 - Cleaning + Audit Layer
-- PURPOSE:
--   Create a cleaned analytical layer from the reconciled database.
--   The cleaning strategy is conservative:
--     - Do NOT impute analytical measures such as rating and size.
--     - Preserve meaningful NULLs.
--     - Add explicit quality flags.
--     - Log every cleaning/flagging decision in an audit table.
--     - Prepare Genre bridge weights for later DW/OLAP analysis.
--
-- RUN AFTER:
--   01_reconciled_schema.sql
--   CSV import into raw.googleplaystore_import
--   02_domain_load.sql
--   03_app_snapshot_etl.sql
--   04_genre_etl.sql
--   05_dqa_queries.sql
-- =========================================================

begin;

-- =========================================================
-- 0. RESET CLEAN SCHEMA ONLY
-- =========================================================
-- This does NOT touch raw or reconciled data.

drop schema if exists clean cascade;
create schema clean;


-- =========================================================
-- 1. AUDIT LOG TABLE
-- =========================================================

create table clean.cleaning_audit_log (
    audit_id bigserial primary key,
    table_name text not null,
    row_pk text not null,
    column_name text,
    issue_type text not null,
    old_value text,
    new_value text,
    action text not null,
    reason text not null,
    created_at timestamptz not null default now()
);


-- =========================================================
-- 2. CLEAN APP SNAPSHOT TABLE
-- =========================================================
-- Important:
--   rating and size_bytes are preserved as NULL when missing.
--   We add flags instead of imputing them, because imputation would
--   distort analytical measures.

create table clean.app_snapshot_clean as
with genre_counts as (
    select
        snapshot_id,
        count(*) as genre_count
    from reconciled.app_snapshot_genre
    group by snapshot_id
),

base as (
    select
        s.snapshot_id,
        s.raw_id,
        s.app_id,
        s.category_id,
        s.app_type_id,
        s.content_rating_id,

        s.rating,
        s.reviews_count,
        s.size_bytes,
        s.installs_count,
        s.price_usd,
        s.last_updated_date,

        s.current_version as current_version_original,
        s.android_version_text as android_version_text_original,

        case
            when s.current_version is null then null
            when trim(s.current_version) = '' then null
            when lower(trim(s.current_version)) in ('nan', 'null', 'n/a', 'na') then null
            else trim(s.current_version)
        end as current_version_clean,

        case
            when s.android_version_text is null then null
            when trim(s.android_version_text) = '' then null
            when lower(trim(s.android_version_text)) in ('nan', 'null', 'n/a', 'na') then null
            else trim(s.android_version_text)
        end as android_version_text_clean,

        atp.app_type_name,
        atp.app_type_name_norm,

        r."Size" as raw_size,
        r."Current Ver" as raw_current_version,
        r."Android Ver" as raw_android_version,
        r."Type" as raw_type,

        coalesce(gc.genre_count, 0) as genre_count

    from reconciled.app_snapshot s
    left join reconciled.app_type atp
        on s.app_type_id = atp.app_type_id
    left join raw.googleplaystore_import r
        on s.raw_id = r.raw_id
    left join genre_counts gc
        on s.snapshot_id = gc.snapshot_id
),

flagged as (
    select
        b.*,

        (b.rating is null) as rating_missing_flag,

        (b.size_bytes is null) as size_missing_flag,

        (
            lower(trim(coalesce(b.raw_size, ''))) = 'varies with device'
        ) as size_varies_with_device_flag,

        (b.app_type_id is null) as app_type_missing_flag,

        (
            b.current_version_clean is null
        ) as current_version_missing_flag,

        (
            b.android_version_text_clean is null
        ) as android_version_missing_flag,

        (
            (b.app_type_name_norm = 'free' and b.price_usd > 0)
            or
            (b.app_type_name_norm = 'paid' and coalesce(b.price_usd, 0) = 0)
        ) as type_price_conflict_flag,

        (
            (b.rating is not null and (b.rating < 0 or b.rating > 5))
            or b.reviews_count < 0
            or b.installs_count < 0
            or b.price_usd < 0
            or b.size_bytes < 0
        ) as invalid_measure_flag,

        (b.genre_count = 0) as genre_missing_flag,

        (b.genre_count > 1) as multiple_genre_flag

    from base b
)

select
    snapshot_id,
    raw_id,
    app_id,
    category_id,
    app_type_id,
    content_rating_id,

    rating,
    reviews_count,
    size_bytes,
    installs_count,
    price_usd,
    last_updated_date,

    current_version_clean as current_version,
    android_version_text_clean as android_version_text,

    genre_count,

    rating_missing_flag,
    size_missing_flag,
    size_varies_with_device_flag,
    app_type_missing_flag,
    current_version_missing_flag,
    android_version_missing_flag,
    type_price_conflict_flag,
    invalid_measure_flag,
    genre_missing_flag,
    multiple_genre_flag,

    (
        rating_missing_flag::int
      + size_missing_flag::int
      + app_type_missing_flag::int
      + current_version_missing_flag::int
      + android_version_missing_flag::int
      + type_price_conflict_flag::int
      + invalid_measure_flag::int
      + genre_missing_flag::int
    ) as dq_issue_count,

    case
        when invalid_measure_flag
          or type_price_conflict_flag
          or genre_missing_flag
        then 'ERROR_REVIEW'
        when rating_missing_flag
          or size_missing_flag
          or app_type_missing_flag
          or current_version_missing_flag
          or android_version_missing_flag
          or multiple_genre_flag
        then 'FLAGGED_OK'
        else 'OK'
    end as dq_status,

    now() as cleaned_at

from flagged;


alter table clean.app_snapshot_clean
add constraint pk_app_snapshot_clean primary key (snapshot_id);

create index idx_app_snapshot_clean_raw_id
    on clean.app_snapshot_clean(raw_id);

create index idx_app_snapshot_clean_app
    on clean.app_snapshot_clean(app_id);

create index idx_app_snapshot_clean_category
    on clean.app_snapshot_clean(category_id);

create index idx_app_snapshot_clean_app_type
    on clean.app_snapshot_clean(app_type_id);

create index idx_app_snapshot_clean_content_rating
    on clean.app_snapshot_clean(content_rating_id);

create index idx_app_snapshot_clean_last_updated_date
    on clean.app_snapshot_clean(last_updated_date);

create index idx_app_snapshot_clean_dq_status
    on clean.app_snapshot_clean(dq_status);


-- =========================================================
-- 3. CLEAN GENRE BRIDGE WITH WEIGHT
-- =========================================================
-- This is the key protection against double counting in analyses
-- involving Genre.
--
-- If a snapshot has:
--   1 genre  -> weight = 1
--   2 genres -> weight = 0.5 for each genre
--
-- Later, in the DW, additive/snapshot measures can be analyzed by Genre
-- using measure * weight.

create table clean.app_snapshot_genre_clean as
select
    sg.snapshot_id,
    sg.genre_id,
    (
        1.0 / nullif(count(*) over (partition by sg.snapshot_id), 0)
    )::numeric(20, 12) as weight,
    now() as cleaned_at
from reconciled.app_snapshot_genre sg;


alter table clean.app_snapshot_genre_clean
add constraint pk_app_snapshot_genre_clean primary key (snapshot_id, genre_id);

alter table clean.app_snapshot_genre_clean
add constraint fk_clean_bridge_snapshot
foreign key (snapshot_id)
references clean.app_snapshot_clean(snapshot_id);

alter table clean.app_snapshot_genre_clean
add constraint fk_clean_bridge_genre
foreign key (genre_id)
references reconciled.genre(genre_id);

create index idx_app_snapshot_genre_clean_snapshot
    on clean.app_snapshot_genre_clean(snapshot_id);

create index idx_app_snapshot_genre_clean_genre
    on clean.app_snapshot_genre_clean(genre_id);


-- =========================================================
-- 4. AUDIT LOG INSERTS
-- =========================================================
-- These logs document the cleaning strategy.
-- Most actions are "PRESERVE_AND_FLAG" because the safest cleaning
-- action is to preserve the original analytical value and add a flag.

-- Rating missing: preserve NULL and flag.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    snapshot_id::text,
    'rating',
    'rating_missing',
    null,
    null,
    'PRESERVE_AND_FLAG',
    'Rating is an analytical measure. Missing ratings are preserved as NULL to avoid biased imputation; rating_missing_flag is set to true.'
from clean.app_snapshot_clean
where rating_missing_flag;


-- Size missing or varies with device: preserve NULL and flag.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'size_bytes',
    case
        when c.size_varies_with_device_flag then 'size_varies_with_device'
        else 'size_missing'
    end,
    r."Size",
    c.size_bytes::text,
    'PRESERVE_AND_FLAG',
    'Application size is missing or reported as "Varies with device". It is preserved as NULL and flagged instead of being imputed.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.size_missing_flag;


-- Missing app type: preserve NULL and flag.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'app_type_id',
    'app_type_missing',
    r."Type",
    null,
    'PRESERVE_AND_FLAG',
    'App type is missing in the source. It is not inferred as Free/Paid without a documented business rule.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.app_type_missing_flag;


-- Current version missing: preserve NULL and flag.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'current_version',
    'current_version_missing',
    r."Current Ver",
    c.current_version,
    'STANDARDIZE_NULL_AND_FLAG',
    'Missing or textual-null current version values are standardized to NULL and flagged.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.current_version_missing_flag;


-- Android version missing: preserve NULL and flag.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'android_version_text',
    'android_version_missing',
    r."Android Ver",
    c.android_version_text,
    'STANDARDIZE_NULL_AND_FLAG',
    'Missing or textual-null Android version values are standardized to NULL and flagged.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.android_version_missing_flag;


-- Type/price conflicts: flag for review.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'app_type_id / price_usd',
    'type_price_conflict',
    concat('type=', coalesce(r."Type", 'NULL'), '; price=', coalesce(r."Price", 'NULL')),
    concat('app_type_id=', coalesce(c.app_type_id::text, 'NULL'), '; price_usd=', coalesce(c.price_usd::text, 'NULL')),
    'FLAG_FOR_REVIEW',
    'Free apps should have price 0 and Paid apps should normally have price greater than 0.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.type_price_conflict_flag;


-- Invalid measures: flag for review.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    c.snapshot_id::text,
    'measures',
    'invalid_measure',
    concat(
        'rating=', coalesce(r."Rating", 'NULL'),
        '; reviews=', coalesce(r."Reviews", 'NULL'),
        '; size=', coalesce(r."Size", 'NULL'),
        '; installs=', coalesce(r."Installs", 'NULL'),
        '; price=', coalesce(r."Price", 'NULL')
    ),
    concat(
        'rating=', coalesce(c.rating::text, 'NULL'),
        '; reviews=', coalesce(c.reviews_count::text, 'NULL'),
        '; size=', coalesce(c.size_bytes::text, 'NULL'),
        '; installs=', coalesce(c.installs_count::text, 'NULL'),
        '; price=', coalesce(c.price_usd::text, 'NULL')
    ),
    'FLAG_FOR_REVIEW',
    'One or more typed measures violate validity rules.'
from clean.app_snapshot_clean c
left join raw.googleplaystore_import r
    on c.raw_id = r.raw_id
where c.invalid_measure_flag;


-- Multiple genres: not an error, but requires weighted bridge in DW.
insert into clean.cleaning_audit_log (
    table_name,
    row_pk,
    column_name,
    issue_type,
    old_value,
    new_value,
    action,
    reason
)
select
    'clean.app_snapshot_clean',
    snapshot_id::text,
    'genre_count',
    'multiple_genre_membership',
    genre_count::text,
    genre_count::text,
    'PRESERVE_AND_USE_WEIGHTED_BRIDGE',
    'The snapshot belongs to multiple genres. This is preserved, and bridge weights are created to avoid double counting in Genre analyses.'
from clean.app_snapshot_clean
where multiple_genre_flag;


-- =========================================================
-- 5. CLEANING SUMMARY VIEWS
-- =========================================================

create or replace view clean.v_cleaning_summary as
select 'clean_app_snapshot_rows' as metric, count(*)::text as value
from clean.app_snapshot_clean

union all
select 'clean_bridge_rows', count(*)::text
from clean.app_snapshot_genre_clean

union all
select 'audit_log_rows', count(*)::text
from clean.cleaning_audit_log

union all
select 'rating_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where rating_missing_flag

union all
select 'size_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where size_missing_flag

union all
select 'size_varies_with_device_flag_rows', count(*)::text
from clean.app_snapshot_clean
where size_varies_with_device_flag

union all
select 'app_type_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where app_type_missing_flag

union all
select 'current_version_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where current_version_missing_flag

union all
select 'android_version_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where android_version_missing_flag

union all
select 'type_price_conflict_flag_rows', count(*)::text
from clean.app_snapshot_clean
where type_price_conflict_flag

union all
select 'invalid_measure_flag_rows', count(*)::text
from clean.app_snapshot_clean
where invalid_measure_flag

union all
select 'genre_missing_flag_rows', count(*)::text
from clean.app_snapshot_clean
where genre_missing_flag

union all
select 'multiple_genre_flag_rows', count(*)::text
from clean.app_snapshot_clean
where multiple_genre_flag

union all
select 'dq_status_ok_rows', count(*)::text
from clean.app_snapshot_clean
where dq_status = 'OK'

union all
select 'dq_status_flagged_ok_rows', count(*)::text
from clean.app_snapshot_clean
where dq_status = 'FLAGGED_OK'

union all
select 'dq_status_error_review_rows', count(*)::text
from clean.app_snapshot_clean
where dq_status = 'ERROR_REVIEW';


create or replace view clean.v_audit_summary_by_issue_type as
select
    issue_type,
    action,
    count(*) as row_count
from clean.cleaning_audit_log
group by issue_type, action
order by row_count desc, issue_type;


create or replace view clean.v_bridge_weight_check as
select
    snapshot_id,
    count(*) as genre_count,
    sum(weight) as weight_sum,
    abs(sum(weight) - 1.0) as weight_error
from clean.app_snapshot_genre_clean
group by snapshot_id
having abs(sum(weight) - 1.0) > 0.000001;


-- =========================================================
-- 6. AFTER-CLEANING DQA SCORECARD
-- =========================================================
-- This scorecard does not pretend that missing rating/size disappeared.
-- Instead, it verifies that known issues are now explicitly managed
-- through flags and audit logs.

create or replace view clean.v_dqa_after_cleaning_scorecard as
with metrics as (

    select
        'Completeness Management' as dimension,
        'rating_missing_values_are_flagged' as metric,
        count(*)::numeric as total_checked,
        count(*) filter (
            where rating is null and rating_missing_flag is not true
        )::numeric as issue_count,
        'All NULL ratings must be explicitly flagged.' as details
    from clean.app_snapshot_clean

    union all

    select
        'Completeness Management',
        'size_missing_values_are_flagged',
        count(*)::numeric,
        count(*) filter (
            where size_bytes is null and size_missing_flag is not true
        )::numeric,
        'All NULL size values must be explicitly flagged.'
    from clean.app_snapshot_clean

    union all

    select
        'Completeness Management',
        'app_type_missing_values_are_flagged',
        count(*)::numeric,
        count(*) filter (
            where app_type_id is null and app_type_missing_flag is not true
        )::numeric,
        'All missing app type values must be explicitly flagged.'
    from clean.app_snapshot_clean

    union all

    select
        'Validity',
        'invalid_measures_remaining',
        count(*)::numeric,
        count(*) filter (where invalid_measure_flag)::numeric,
        'Invalid typed measures should not exist after the reconciled ETL.'
    from clean.app_snapshot_clean

    union all

    select
        'Consistency',
        'type_price_conflicts_remaining',
        count(*)::numeric,
        count(*) filter (where type_price_conflict_flag)::numeric,
        'Free/Paid type should be consistent with price.'
    from clean.app_snapshot_clean

    union all

    select
        'Consistency',
        'genre_missing_remaining',
        count(*)::numeric,
        count(*) filter (where genre_missing_flag)::numeric,
        'Every app snapshot should have at least one genre.'
    from clean.app_snapshot_clean

    union all

    select
        'Many-to-Many Integrity',
        'genre_bridge_weight_errors',
        count(*)::numeric,
        (select count(*)::numeric from clean.v_bridge_weight_check),
        'For each snapshot, the sum of Genre bridge weights must be equal to 1.'
    from clean.app_snapshot_clean

    union all

    select
        'Reconciliation',
        'clean_rows_match_reconciled_rows',
        1::numeric,
        case
            when
                (select count(*) from clean.app_snapshot_clean)
                =
                (select count(*) from reconciled.app_snapshot)
            then 0::numeric
            else 1::numeric
        end,
        'Clean layer should preserve the reconciled snapshot grain.'
)
select
    dimension,
    metric,
    total_checked,
    issue_count,
    case
        when total_checked is null or total_checked = 0 then null
        else round(1 - (issue_count / total_checked), 4)
    end as score,
    case
        when total_checked is null or total_checked = 0 then 'INFO'
        when round(1 - (issue_count / total_checked), 4) >= 0.95 then 'GREEN'
        when round(1 - (issue_count / total_checked), 4) >= 0.80 then 'YELLOW'
        else 'RED'
    end as severity,
    details
from metrics;


commit;