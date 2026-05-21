-- =========================================================
-- FILE: verifyPhase2.sql
-- PROJECT: Google Play Store Data Warehouse
-- PHASE: Phase 2 - Verification Script
-- PURPOSE:
--   Verify Phase 2 after running:
--     05_dqa_queries.sql
--     06_cleaning_and_audit.sql
--     07_dw_star_schema.sql
--     08_dw_etl.sql
--
-- HOW TO USE:
--   Run this file after the full Phase 2 pipeline.
--   In Supabase SQL Editor, run each SELECT block one by one
--   if you need screenshots/evidence for the report.
--
-- NOTE:
--   Exact expected counts are based on the provided Google Play Store CSV.
-- =========================================================


-- =========================================================
-- 1. PHASE 2 CORE ROW COUNT CHECKS
-- =========================================================
-- Expected key counts:
--   clean.app_snapshot_clean              = 10840
--   clean.app_snapshot_genre_clean        = 11288
--   dw.fact_app_snapshot                  = 10840
--   dw.bridge_app_snapshot_genre          = 11288
--   dw.dim_app                            = 9638
--   dw.dim_category                       = 33
--   dw.dim_app_type                       = 3  -- Free, Paid, Unknown
--   dw.dim_content_rating                 = 6
--   dw.dim_genre                          = 53

select
    'P2-COUNT-01' as check_id,
    'raw rows are preserved' as check_name,
    10841::numeric as expected_value,
    (select count(*) from raw.googleplaystore_import)::numeric as actual_value,
    case when (select count(*) from raw.googleplaystore_import) = 10841 then 'PASS' else 'FAIL' end as status

union all
select
    'P2-COUNT-02',
    'reconciled snapshot rows',
    10840::numeric,
    (select count(*) from reconciled.app_snapshot)::numeric,
    case when (select count(*) from reconciled.app_snapshot) = 10840 then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-03',
    'clean snapshot rows match reconciled snapshot rows',
    (select count(*) from reconciled.app_snapshot)::numeric,
    (select count(*) from clean.app_snapshot_clean)::numeric,
    case
        when (select count(*) from clean.app_snapshot_clean)
           = (select count(*) from reconciled.app_snapshot)
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-COUNT-04',
    'clean bridge rows match reconciled bridge rows',
    (select count(*) from reconciled.app_snapshot_genre)::numeric,
    (select count(*) from clean.app_snapshot_genre_clean)::numeric,
    case
        when (select count(*) from clean.app_snapshot_genre_clean)
           = (select count(*) from reconciled.app_snapshot_genre)
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-COUNT-05',
    'fact rows match clean snapshot rows',
    (select count(*) from clean.app_snapshot_clean)::numeric,
    (select count(*) from dw.fact_app_snapshot)::numeric,
    case
        when (select count(*) from dw.fact_app_snapshot)
           = (select count(*) from clean.app_snapshot_clean)
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-COUNT-06',
    'dw bridge rows match clean bridge rows',
    (select count(*) from clean.app_snapshot_genre_clean)::numeric,
    (select count(*) from dw.bridge_app_snapshot_genre)::numeric,
    case
        when (select count(*) from dw.bridge_app_snapshot_genre)
           = (select count(*) from clean.app_snapshot_genre_clean)
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-COUNT-07',
    'dim_app rows match reconciled.app rows',
    (select count(*) from reconciled.app)::numeric,
    (select count(*) from dw.dim_app)::numeric,
    case when (select count(*) from dw.dim_app) = (select count(*) from reconciled.app) then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-08',
    'dim_category rows match reconciled.category rows',
    (select count(*) from reconciled.category)::numeric,
    (select count(*) from dw.dim_category)::numeric,
    case when (select count(*) from dw.dim_category) = (select count(*) from reconciled.category) then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-09',
    'dim_app_type rows include Unknown technical row',
    ((select count(*) from reconciled.app_type) + 1)::numeric,
    (select count(*) from dw.dim_app_type)::numeric,
    case when (select count(*) from dw.dim_app_type) = ((select count(*) from reconciled.app_type) + 1) then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-10',
    'dim_content_rating rows match reconciled.content_rating rows',
    (select count(*) from reconciled.content_rating)::numeric,
    (select count(*) from dw.dim_content_rating)::numeric,
    case when (select count(*) from dw.dim_content_rating) = (select count(*) from reconciled.content_rating) then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-11',
    'dim_genre rows match reconciled.genre rows',
    (select count(*) from reconciled.genre)::numeric,
    (select count(*) from dw.dim_genre)::numeric,
    case when (select count(*) from dw.dim_genre) = (select count(*) from reconciled.genre) then 'PASS' else 'FAIL' end

union all
select
    'P2-COUNT-12',
    'dim_last_updated_date rows match distinct clean dates',
    (select count(distinct last_updated_date) from clean.app_snapshot_clean where last_updated_date is not null)::numeric,
    (select count(*) from dw.dim_last_updated_date)::numeric,
    case
        when (select count(*) from dw.dim_last_updated_date)
           = (select count(distinct last_updated_date) from clean.app_snapshot_clean where last_updated_date is not null)
        then 'PASS' else 'FAIL'
    end
order by check_id;


-- =========================================================
-- 2. CLEANING FLAG AND AUDIT CHECKS
-- =========================================================
-- Expected with provided CSV:
--   rating_missing_flag_rows            = 1474
--   size_missing_flag_rows              = 1695
--   size_varies_with_device_flag_rows   = 1695
--   app_type_missing_flag_rows          = 1
--   current_version_missing_flag_rows   = 8
--   android_version_missing_flag_rows   = 2
--   type_price_conflict_flag_rows       = 0
--   invalid_measure_flag_rows           = 0
--   genre_missing_flag_rows             = 0
--   multiple_genre_flag_rows            = 448
--   audit_log_rows                      = 3628
--   dq_status OK                        = 7347
--   dq_status FLAGGED_OK                = 3493
--   dq_status ERROR_REVIEW              = 0

select
    'P2-CLEAN-01' as check_id,
    'NULL ratings are flagged' as check_name,
    0::numeric as expected_issue_count,
    count(*) filter (where rating is null and rating_missing_flag is not true)::numeric as actual_issue_count,
    case when count(*) filter (where rating is null and rating_missing_flag is not true) = 0 then 'PASS' else 'FAIL' end as status
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-02',
    'NULL sizes are flagged',
    0::numeric,
    count(*) filter (where size_bytes is null and size_missing_flag is not true)::numeric,
    case when count(*) filter (where size_bytes is null and size_missing_flag is not true) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-03',
    'missing app types are flagged',
    0::numeric,
    count(*) filter (where app_type_id is null and app_type_missing_flag is not true)::numeric,
    case when count(*) filter (where app_type_id is null and app_type_missing_flag is not true) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-04',
    'invalid measures remaining',
    0::numeric,
    count(*) filter (where invalid_measure_flag)::numeric,
    case when count(*) filter (where invalid_measure_flag) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-05',
    'type price conflicts remaining',
    0::numeric,
    count(*) filter (where type_price_conflict_flag)::numeric,
    case when count(*) filter (where type_price_conflict_flag) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-06',
    'snapshots without genre remaining',
    0::numeric,
    count(*) filter (where genre_missing_flag)::numeric,
    case when count(*) filter (where genre_missing_flag) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_clean

union all
select
    'P2-CLEAN-07',
    'audit log rows match all logged flag rows',
    (
        select
            count(*) filter (where rating_missing_flag)
          + count(*) filter (where size_missing_flag)
          + count(*) filter (where app_type_missing_flag)
          + count(*) filter (where current_version_missing_flag)
          + count(*) filter (where android_version_missing_flag)
          + count(*) filter (where type_price_conflict_flag)
          + count(*) filter (where invalid_measure_flag)
          + count(*) filter (where multiple_genre_flag)
        from clean.app_snapshot_clean
    )::numeric,
    (select count(*) from clean.cleaning_audit_log)::numeric,
    case
        when (select count(*) from clean.cleaning_audit_log)
           = (
                select
                    count(*) filter (where rating_missing_flag)
                  + count(*) filter (where size_missing_flag)
                  + count(*) filter (where app_type_missing_flag)
                  + count(*) filter (where current_version_missing_flag)
                  + count(*) filter (where android_version_missing_flag)
                  + count(*) filter (where type_price_conflict_flag)
                  + count(*) filter (where invalid_measure_flag)
                  + count(*) filter (where multiple_genre_flag)
                from clean.app_snapshot_clean
             )
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-CLEAN-08',
    'ERROR_REVIEW rows after cleaning',
    0::numeric,
    (select count(*) from clean.app_snapshot_clean where dq_status = 'ERROR_REVIEW')::numeric,
    case when (select count(*) from clean.app_snapshot_clean where dq_status = 'ERROR_REVIEW') = 0 then 'PASS' else 'FAIL' end
order by check_id;


-- =========================================================
-- 3. CLEAN BRIDGE INTEGRITY AND WEIGHT CHECKS
-- =========================================================

select
    'P2-BRIDGE-01' as check_id,
    'clean bridge orphan snapshot rows' as check_name,
    0::numeric as expected_issue_count,
    count(*) filter (where c.snapshot_id is null)::numeric as actual_issue_count,
    case when count(*) filter (where c.snapshot_id is null) = 0 then 'PASS' else 'FAIL' end as status
from clean.app_snapshot_genre_clean cb
left join clean.app_snapshot_clean c
    on cb.snapshot_id = c.snapshot_id

union all
select
    'P2-BRIDGE-02',
    'clean bridge orphan genre rows',
    0::numeric,
    count(*) filter (where g.genre_id is null)::numeric,
    case when count(*) filter (where g.genre_id is null) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_genre_clean cb
left join reconciled.genre g
    on cb.genre_id = g.genre_id

union all
select
    'P2-BRIDGE-03',
    'duplicate clean bridge pairs',
    0::numeric,
    (
        select count(*)::numeric
        from (
            select snapshot_id, genre_id
            from clean.app_snapshot_genre_clean
            group by snapshot_id, genre_id
            having count(*) > 1
        ) d
    ),
    case
        when (
            select count(*)
            from (
                select snapshot_id, genre_id
                from clean.app_snapshot_genre_clean
                group by snapshot_id, genre_id
                having count(*) > 1
            ) d
        ) = 0
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-BRIDGE-04',
    'invalid clean bridge weights',
    0::numeric,
    count(*) filter (where weight <= 0 or weight > 1)::numeric,
    case when count(*) filter (where weight <= 0 or weight > 1) = 0 then 'PASS' else 'FAIL' end
from clean.app_snapshot_genre_clean

union all
select
    'P2-BRIDGE-05',
    'clean bridge weight sum errors',
    0::numeric,
    (select count(*) from clean.v_bridge_weight_check)::numeric,
    case when (select count(*) from clean.v_bridge_weight_check) = 0 then 'PASS' else 'FAIL' end
order by check_id;


-- =========================================================
-- 4. DW FOREIGN KEY, DUPLICATE, AND UNKNOWN ROW CHECKS
-- =========================================================

select
    'P2-DW-01' as check_id,
    'fact orphan app_key rows' as check_name,
    0::numeric as expected_issue_count,
    count(*) filter (where da.app_key is null)::numeric as actual_issue_count,
    case when count(*) filter (where da.app_key is null) = 0 then 'PASS' else 'FAIL' end as status
from dw.fact_app_snapshot f
left join dw.dim_app da
    on f.app_key = da.app_key

union all
select
    'P2-DW-02',
    'fact orphan category_key rows',
    0::numeric,
    count(*) filter (where dc.category_key is null)::numeric,
    case when count(*) filter (where dc.category_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.fact_app_snapshot f
left join dw.dim_category dc
    on f.category_key = dc.category_key

union all
select
    'P2-DW-03',
    'fact orphan app_type_key rows',
    0::numeric,
    count(*) filter (where dat.app_type_key is null)::numeric,
    case when count(*) filter (where dat.app_type_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.fact_app_snapshot f
left join dw.dim_app_type dat
    on f.app_type_key = dat.app_type_key

union all
select
    'P2-DW-04',
    'fact orphan content_rating_key rows',
    0::numeric,
    count(*) filter (where dcr.content_rating_key is null)::numeric,
    case when count(*) filter (where dcr.content_rating_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.fact_app_snapshot f
left join dw.dim_content_rating dcr
    on f.content_rating_key = dcr.content_rating_key

union all
select
    'P2-DW-05',
    'fact orphan date_key rows',
    0::numeric,
    count(*) filter (where dd.last_updated_date_key is null)::numeric,
    case when count(*) filter (where dd.last_updated_date_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.fact_app_snapshot f
left join dw.dim_last_updated_date dd
    on f.last_updated_date_key = dd.last_updated_date_key

union all
select
    'P2-DW-06',
    'bridge orphan fact rows',
    0::numeric,
    count(*) filter (where f.app_snapshot_key is null)::numeric,
    case when count(*) filter (where f.app_snapshot_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.bridge_app_snapshot_genre b
left join dw.fact_app_snapshot f
    on b.app_snapshot_key = f.app_snapshot_key

union all
select
    'P2-DW-07',
    'bridge orphan genre rows',
    0::numeric,
    count(*) filter (where g.genre_key is null)::numeric,
    case when count(*) filter (where g.genre_key is null) = 0 then 'PASS' else 'FAIL' end
from dw.bridge_app_snapshot_genre b
left join dw.dim_genre g
    on b.genre_key = g.genre_key

union all
select
    'P2-DW-08',
    'duplicate fact snapshot_id rows',
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
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-DW-09',
    'unknown app type fact rows match clean missing app type rows',
    (select count(*) from clean.app_snapshot_clean where app_type_missing_flag)::numeric,
    (
        select count(*)
        from dw.fact_app_snapshot f
        join dw.dim_app_type dat
            on f.app_type_key = dat.app_type_key
        where dat.app_type_name_norm = 'unknown'
    )::numeric,
    case
        when (
            select count(*)
            from dw.fact_app_snapshot f
            join dw.dim_app_type dat
                on f.app_type_key = dat.app_type_key
            where dat.app_type_name_norm = 'unknown'
        ) = (select count(*) from clean.app_snapshot_clean where app_type_missing_flag)
        then 'PASS' else 'FAIL'
    end
order by check_id;


-- =========================================================
-- 5. DW BRIDGE WEIGHTED AGGREGATION CHECKS
-- =========================================================
-- These checks prove that the weighted bridge avoids double counting.

select
    'P2-WEIGHT-01' as check_id,
    'dw bridge weight sum errors' as check_name,
    0::numeric as expected_issue_count,
    (select count(*) from dw.v_bridge_weight_check)::numeric as actual_issue_count,
    case when (select count(*) from dw.v_bridge_weight_check) = 0 then 'PASS' else 'FAIL' end as status

union all
select
    'P2-WEIGHT-02',
    'weighted snapshot count equals fact row count',
    (select count(*) from dw.fact_app_snapshot)::numeric,
    (select round(sum(weight), 6) from dw.bridge_app_snapshot_genre)::numeric,
    case
        when abs(
            (select sum(weight) from dw.bridge_app_snapshot_genre)
            -
            (select count(*) from dw.fact_app_snapshot)::numeric
        ) <= 0.000001
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-WEIGHT-03',
    'weighted reviews equal fact reviews',
    (select coalesce(sum(reviews_count), 0) from dw.fact_app_snapshot)::numeric,
    (select round(coalesce(sum(weighted_reviews_count), 0), 6) from dw.v_genre_fractional_analysis)::numeric,
    case
        when abs(
            (select coalesce(sum(weighted_reviews_count), 0) from dw.v_genre_fractional_analysis)
            -
            (select coalesce(sum(reviews_count), 0)::numeric from dw.fact_app_snapshot)
        ) <= 100
        then 'PASS' else 'FAIL'
    end

union all
select
    'P2-WEIGHT-04',
    'weighted installs equal fact installs',
    (select coalesce(sum(installs_count), 0) from dw.fact_app_snapshot)::numeric,
    (select round(coalesce(sum(weighted_installs_count), 0), 6) from dw.v_genre_fractional_analysis)::numeric,
    case
        when abs(
            (select coalesce(sum(weighted_installs_count), 0) from dw.v_genre_fractional_analysis)
            -
            (select coalesce(sum(installs_count), 0)::numeric from dw.fact_app_snapshot)
        ) <= 100
        then 'PASS' else 'FAIL'
    end
order by check_id;


-- =========================================================
-- 6. SUMMARY VIEWS FOR SCREENSHOTS / REPORT EVIDENCE
-- =========================================================

-- 6.1 Baseline DQA results from file 05.
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

-- 6.2 Cleaning summary from file 06.
select *
from clean.v_cleaning_summary;

-- 6.3 Audit summary from file 06.
select *
from clean.v_audit_summary_by_issue_type;

-- 6.4 After-cleaning DQA scorecard from file 06.
select *
from clean.v_dqa_after_cleaning_scorecard
order by dimension, metric;

-- 6.5 DW load summary from file 08.
select *
from dw.v_dw_load_summary;

-- 6.6 DW integrity checks from file 08.
select *
from dw.v_dw_integrity_checks;

-- 6.7 Top 10 weighted Genre KPIs from file 08.
select *
from dw.v_genre_weighted_kpis
order by weighted_installs_count desc
limit 10;


-- =========================================================
-- 7. EXPECTED EMPTY RESULT SETS
-- =========================================================
-- Each query below should return 0 rows.

-- 7.1 Clean bridge weight errors: expected 0 rows.
select *
from clean.v_bridge_weight_check;

-- 7.2 DW bridge weight errors: expected 0 rows.
select *
from dw.v_bridge_weight_check;

-- 7.3 After-cleaning scorecard non-green metrics: expected 0 rows.
select *
from clean.v_dqa_after_cleaning_scorecard
where severity not in ('GREEN', 'INFO');

-- 7.4 DW integrity failures: expected 0 rows.
select *
from dw.v_dw_integrity_checks
where status <> 'PASS';
