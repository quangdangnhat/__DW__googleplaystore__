-- =========================================================
-- 05_dqa_queries.sql
-- Project: Google Play Store
-- Purpose:
--   Data Quality Assessment queries on the reconciled layer
-- Dimensions covered:
--   1) Completeness
--   2) Uniqueness
--   3) Validity
--   4) Consistency
--   5) Timeliness
-- =========================================================

-- =========================================================
-- 0) OVERVIEW COUNTS
-- =========================================================
select 'raw_rows' as metric, count(*)::numeric as value
from raw.googleplaystore_import

union all
select 'app_rows', count(*)::numeric
from reconciled.app

union all
select 'app_snapshot_rows', count(*)::numeric
from reconciled.app_snapshot

union all
select 'genre_rows', count(*)::numeric
from reconciled.genre

union all
select 'app_snapshot_genre_rows', count(*)::numeric
from reconciled.app_snapshot_genre
order by metric;

-- =========================================================
-- 1) COMPLETENESS
-- =========================================================

-- 1.1 Null / missing counts on key snapshot attributes
select
    count(*) as total_rows,
    count(rating) as rating_not_null,
    count(reviews_count) as reviews_not_null,
    count(size_bytes) as size_not_null,
    count(installs_count) as installs_not_null,
    count(price_usd) as price_not_null,
    count(last_updated_date) as last_updated_not_null,
    count(current_version) as current_version_not_null,
    count(android_version_text) as android_version_not_null
from reconciled.app_snapshot;

-- 1.2 Completeness ratio by attribute
select
    'rating' as attribute,
    round(count(rating)::numeric / count(*)::numeric, 4) as completeness_score
from reconciled.app_snapshot

union all
select
    'reviews_count',
    round(count(reviews_count)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'size_bytes',
    round(count(size_bytes)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'installs_count',
    round(count(installs_count)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'price_usd',
    round(count(price_usd)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'last_updated_date',
    round(count(last_updated_date)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'current_version',
    round(count(current_version)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot

union all
select
    'android_version_text',
    round(count(android_version_text)::numeric / count(*)::numeric, 4)
from reconciled.app_snapshot
order by attribute;

-- 1.3 Rows with at least one major missing value
select
    count(*) as rows_with_any_major_missing_value
from reconciled.app_snapshot
where rating is null
   or reviews_count is null
   or installs_count is null
   or price_usd is null
   or last_updated_date is null;

-- =========================================================
-- 2) UNIQUENESS
-- =========================================================

-- 2.1 Check duplicate normalized app names in master table
select
    app_name_norm,
    count(*) as duplicate_count
from reconciled.app
group by app_name_norm
having count(*) > 1
order by duplicate_count desc, app_name_norm;

-- 2.2 Check raw_id uniqueness in snapshot table
select
    raw_id,
    count(*) as duplicate_count
from reconciled.app_snapshot
group by raw_id
having count(*) > 1
order by duplicate_count desc, raw_id;

-- 2.3 Check duplicate snapshot-genre relationships
select
    snapshot_id,
    genre_id,
    count(*) as duplicate_count
from reconciled.app_snapshot_genre
group by snapshot_id, genre_id
having count(*) > 1
order by duplicate_count desc, snapshot_id, genre_id;

-- 2.4 Duplicate app names in raw source
select
    lower(trim("App")) as app_name_norm,
    count(*) as occurrence_count
from raw.googleplaystore_import
where "App" is not null
  and trim("App") <> ''
group by lower(trim("App"))
having count(*) > 1
order by occurrence_count desc, app_name_norm;

-- 2.5 Uniqueness score for app master
select
    round(
        (
            select count(distinct app_name_norm)::numeric
            from reconciled.app
        ) /
        nullif(
            (
                select count(*)::numeric
                from reconciled.app
            ),
            0
        ),
        4
    ) as app_master_uniqueness_score;

-- =========================================================
-- 3) VALIDITY
-- =========================================================

-- 3.1 Invalid rating values (should be between 0 and 5)
select
    count(*) as invalid_rating_rows
from reconciled.app_snapshot
where rating is not null
  and (rating < 0 or rating > 5);

-- 3.2 Invalid reviews_count values (should be non-negative)
select
    count(*) as invalid_reviews_rows
from reconciled.app_snapshot
where reviews_count is not null
  and reviews_count < 0;

-- 3.3 Invalid installs_count values (should be non-negative)
select
    count(*) as invalid_installs_rows
from reconciled.app_snapshot
where installs_count is not null
  and installs_count < 0;

-- 3.4 Invalid price values (should be non-negative)
select
    count(*) as invalid_price_rows
from reconciled.app_snapshot
where price_usd is not null
  and price_usd < 0;

-- 3.5 Invalid size values (should be non-negative)
select
    count(*) as invalid_size_rows
from reconciled.app_snapshot
where size_bytes is not null
  and size_bytes < 0;

-- 3.6 Suspicious category values
select
    c.category_name,
    count(*) as occurrence_count
from reconciled.app_snapshot s
join reconciled.category c
    on s.category_id = c.category_id
where c.category_name ~ '^[0-9]+(\.[0-9]+)?$'
group by c.category_name
order by occurrence_count desc, c.category_name;

-- 3.7 Suspicious app type values outside expected domain
select
    atp.app_type_name,
    count(*) as occurrence_count
from reconciled.app_snapshot s
join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id
where lower(atp.app_type_name) not in ('free', 'paid')
group by atp.app_type_name
order by occurrence_count desc, atp.app_type_name;

-- 3.8 Suspicious content ratings outside expected domain
select
    cr.content_rating_name,
    count(*) as occurrence_count
from reconciled.app_snapshot s
join reconciled.content_rating cr
    on s.content_rating_id = cr.content_rating_id
where lower(cr.content_rating_name) not in
    ('everyone', 'everyone 10+', 'teen', 'mature 17+', 'adults only 18+', 'unrated')
group by cr.content_rating_name
order by occurrence_count desc, cr.content_rating_name;

-- 3.9 Invalid genre values containing digits
select
    genre_name
from reconciled.genre
where genre_name ~ '[0-9]'
order by genre_name;

-- 3.10 Validity scores
select
    'rating_range' as check_name,
    round(
        1 - (
            count(*) filter (where rating is not null and (rating < 0 or rating > 5))::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    ) as validity_score
from reconciled.app_snapshot

union all
select
    'reviews_nonnegative',
    round(
        1 - (
            count(*) filter (where reviews_count is not null and reviews_count < 0)::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    )
from reconciled.app_snapshot

union all
select
    'installs_nonnegative',
    round(
        1 - (
            count(*) filter (where installs_count is not null and installs_count < 0)::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    )
from reconciled.app_snapshot

union all
select
    'price_nonnegative',
    round(
        1 - (
            count(*) filter (where price_usd is not null and price_usd < 0)::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    )
from reconciled.app_snapshot

union all
select
    'size_nonnegative',
    round(
        1 - (
            count(*) filter (where size_bytes is not null and size_bytes < 0)::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    )
from reconciled.app_snapshot
order by check_name;

-- =========================================================
-- 4) CONSISTENCY
-- =========================================================

-- 4.1 Paid apps with zero price
select
    count(*) as paid_apps_with_zero_price
from reconciled.app_snapshot s
join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id
where lower(atp.app_type_name) = 'paid'
  and coalesce(price_usd, 0) = 0;

-- 4.2 Free apps with positive price
select
    count(*) as free_apps_with_positive_price
from reconciled.app_snapshot s
join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id
where lower(atp.app_type_name) = 'free'
  and coalesce(price_usd, 0) > 0;

-- 4.3 Missing domain references
select
    count(*) filter (where app_id is null) as missing_app_fk,
    count(*) filter (where category_id is null) as missing_category_fk,
    count(*) filter (where app_type_id is null) as missing_app_type_fk,
    count(*) filter (where content_rating_id is null) as missing_content_rating_fk
from reconciled.app_snapshot;

-- 4.4 Snapshot rows without any mapped genre
select
    count(*) as snapshots_without_genre
from reconciled.app_snapshot s
left join reconciled.app_snapshot_genre sg
    on s.snapshot_id = sg.snapshot_id
where sg.snapshot_id is null;

-- 4.5 Consistency scores
select
    'paid_price_consistency' as check_name,
    round(
        1 - (
            count(*) filter (
                where lower(atp.app_type_name) = 'paid'
                  and coalesce(price_usd, 0) = 0
            )::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    ) as consistency_score
from reconciled.app_snapshot s
join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id

union all
select
    'free_price_consistency',
    round(
        1 - (
            count(*) filter (
                where lower(atp.app_type_name) = 'free'
                  and coalesce(price_usd, 0) > 0
            )::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    )
from reconciled.app_snapshot s
join reconciled.app_type atp
    on s.app_type_id = atp.app_type_id
order by check_name;

-- =========================================================
-- 5) TIMELINESS
-- =========================================================

-- 5.1 Distribution of last_updated_date
select
    min(last_updated_date) as min_last_updated_date,
    max(last_updated_date) as max_last_updated_date
from reconciled.app_snapshot;

-- 5.2 Future dates
select
    count(*) as future_dated_rows
from reconciled.app_snapshot
where last_updated_date is not null
  and last_updated_date > current_date;

-- 5.3 Rows older than a threshold
select
    count(*) as rows_older_than_5_years
from reconciled.app_snapshot
where last_updated_date is not null
  and last_updated_date < (current_date - interval '5 years');

-- 5.4 Timeliness score
select
    round(
        1 - (
            count(*) filter (
                where last_updated_date is not null
                  and last_updated_date > current_date
            )::numeric
            / nullif(count(*)::numeric, 0)
        ),
        4
    ) as timeliness_score
from reconciled.app_snapshot;

-- =========================================================
-- 6) OVERALL DQA SCORECARD
-- =========================================================
with metrics as (
    select
        'completeness' as dimension,
        round(
            (
                (
                    count(rating)::numeric +
                    count(reviews_count)::numeric +
                    count(size_bytes)::numeric +
                    count(installs_count)::numeric +
                    count(price_usd)::numeric +
                    count(last_updated_date)::numeric
                ) /
                nullif((count(*) * 6)::numeric, 0)
            ),
            4
        ) as score
    from reconciled.app_snapshot

    union all

    select
        'uniqueness',
        round(
            (
                select count(distinct app_name_norm)::numeric
                from reconciled.app
            ) /
            nullif(
                (
                    select count(*)::numeric
                    from reconciled.app
                ),
                0
            ),
            4
        )

    union all

    select
        'validity',
        round(
            (
                (
                    (
                        count(*) filter (where rating is null or (rating between 0 and 5))::numeric +
                        count(*) filter (where reviews_count is null or reviews_count >= 0)::numeric +
                        count(*) filter (where installs_count is null or installs_count >= 0)::numeric +
                        count(*) filter (where price_usd is null or price_usd >= 0)::numeric +
                        count(*) filter (where size_bytes is null or size_bytes >= 0)::numeric
                    ) /
                    nullif((count(*) * 5)::numeric, 0)
                )
            ),
            4
        )
    from reconciled.app_snapshot

    union all

    select
        'consistency',
        round(
            (
                count(*) filter (
                    where not (
                        (lower(atp.app_type_name) = 'paid' and coalesce(price_usd, 0) = 0)
                        or
                        (lower(atp.app_type_name) = 'free' and coalesce(price_usd, 0) > 0)
                    )
                )::numeric
                / nullif(count(*)::numeric, 0)
            ),
            4
        )
    from reconciled.app_snapshot s
    join reconciled.app_type atp
        on s.app_type_id = atp.app_type_id

    union all

    select
        'timeliness',
        round(
            count(*) filter (
                where last_updated_date is null or last_updated_date <= current_date
            )::numeric
            / nullif(count(*)::numeric, 0),
            4
        )
    from reconciled.app_snapshot
)
select *
from metrics
order by dimension;

-- 6.2 Overall average score
with metrics as (
    select
        'completeness' as dimension,
        round(
            (
                (
                    count(rating)::numeric +
                    count(reviews_count)::numeric +
                    count(size_bytes)::numeric +
                    count(installs_count)::numeric +
                    count(price_usd)::numeric +
                    count(last_updated_date)::numeric
                ) /
                nullif((count(*) * 6)::numeric, 0)
            ),
            4
        ) as score
    from reconciled.app_snapshot

    union all

    select
        'uniqueness',
        round(
            (
                select count(distinct app_name_norm)::numeric
                from reconciled.app
            ) /
            nullif(
                (
                    select count(*)::numeric
                    from reconciled.app
                ),
                0
            ),
            4
        )

    union all

    select
        'validity',
        round(
            (
                (
                    (
                        count(*) filter (where rating is null or (rating between 0 and 5))::numeric +
                        count(*) filter (where reviews_count is null or reviews_count >= 0)::numeric +
                        count(*) filter (where installs_count is null or installs_count >= 0)::numeric +
                        count(*) filter (where price_usd is null or price_usd >= 0)::numeric +
                        count(*) filter (where size_bytes is null or size_bytes >= 0)::numeric
                    ) /
                    nullif((count(*) * 5)::numeric, 0)
                )
            ),
            4
        )
    from reconciled.app_snapshot

    union all

    select
        'consistency',
        round(
            (
                count(*) filter (
                    where not (
                        (lower(atp.app_type_name) = 'paid' and coalesce(price_usd, 0) = 0)
                        or
                        (lower(atp.app_type_name) = 'free' and coalesce(price_usd, 0) > 0)
                    )
                )::numeric
                / nullif(count(*)::numeric, 0)
            ),
            4
        )
    from reconciled.app_snapshot s
    join reconciled.app_type atp
        on s.app_type_id = atp.app_type_id

    union all

    select
        'timeliness',
        round(
            count(*) filter (
                where last_updated_date is null or last_updated_date <= current_date
            )::numeric
            / nullif(count(*)::numeric, 0),
            4
        )
    from reconciled.app_snapshot
)
select
    round(avg(score), 4) as overall_dqa_score
from metrics;