-- =========================================================
-- FILE: 03_app_snapshot_etl.sql
-- PURPOSE: Populate app_snapshot from raw_googleplaystore
-- =========================================================

WITH clean_source AS (
    SELECT
        r.raw_id,
        TRIM(r.app_raw) AS app_name,
        LOWER(TRIM(r.app_raw)) AS app_name_normalized,
        NULLIF(TRIM(r.category_raw), '') AS category_name,
        NULLIF(TRIM(r.type_raw), '') AS app_type_name,
        NULLIF(TRIM(r.content_rating_raw), '') AS content_rating_name,
        NULLIF(TRIM(r.android_ver_raw), '') AS android_version_label,
        NULLIF(TRIM(r.current_ver_raw), '') AS current_version,
        NULLIF(TRIM(r.size_raw), '') AS size_label_raw,

        CASE
            WHEN NULLIF(TRIM(r.rating_raw), '') IS NOT NULL
                 AND TRIM(r.rating_raw) ~ '^[0-9]+(\.[0-9]+)?$'
            THEN TRIM(r.rating_raw)::NUMERIC(3,2)
            ELSE NULL
        END AS rating,

        CASE
            WHEN NULLIF(TRIM(r.reviews_raw), '') IS NOT NULL
                 AND TRIM(r.reviews_raw) ~ '^[0-9]+$'
            THEN TRIM(r.reviews_raw)::BIGINT
            ELSE NULL
        END AS reviews_count,

        CASE
            WHEN REGEXP_REPLACE(COALESCE(r.installs_raw, ''), '[^0-9]', '', 'g') <> ''
            THEN REGEXP_REPLACE(r.installs_raw, '[^0-9]', '', 'g')::BIGINT
            ELSE NULL
        END AS installs_count,

        CASE
            WHEN REGEXP_REPLACE(COALESCE(r.price_raw, ''), '[^0-9\.]', '', 'g') <> ''
            THEN REGEXP_REPLACE(r.price_raw, '[^0-9\.]', '', 'g')::NUMERIC(10,2)
            ELSE NULL
        END AS price_amount,

        CASE
            WHEN TRIM(r.size_raw) ~ '^[0-9]+(\.[0-9]+)?M$'
            THEN REPLACE(TRIM(r.size_raw), 'M', '')::NUMERIC(10,2)

            WHEN TRIM(r.size_raw) ~ '^[0-9]+(\.[0-9]+)?k$'
            THEN (REPLACE(TRIM(r.size_raw), 'k', '')::NUMERIC(10,2) / 1024)

            WHEN TRIM(r.size_raw) = 'Varies with device'
            THEN NULL

            ELSE NULL
        END AS size_mb,

        CASE
            WHEN TRIM(r.last_updated_raw) ~ '^[A-Za-z]+ [0-9]{1,2}, [0-9]{4}$'
            THEN TO_DATE(TRIM(r.last_updated_raw), 'FMMonth FMDD, YYYY')

            WHEN TRIM(r.last_updated_raw) ~ '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}$'
            THEN TO_DATE(TRIM(r.last_updated_raw), 'DD-Mon-YY')

            ELSE NULL
        END AS last_updated_date

    FROM raw_googleplaystore r
    WHERE r.app_raw IS NOT NULL
      AND TRIM(r.app_raw) <> ''
      AND COALESCE(TRIM(r.category_raw), '') <> '1.9'
)

INSERT INTO app_snapshot (
    app_id,
    category_id,
    app_type_id,
    content_rating_id,
    android_version_id,
    rating,
    reviews_count,
    installs_count,
    price_amount,
    size_mb,
    size_label_raw,
    current_version,
    last_updated_date,
    raw_id
)
SELECT
    a.app_id,
    c.category_id,
    t.app_type_id,
    cr.content_rating_id,
    av.android_version_id,
    cs.rating,
    cs.reviews_count,
    cs.installs_count,
    cs.price_amount,
    cs.size_mb,
    cs.size_label_raw,
    cs.current_version,
    cs.last_updated_date,
    cs.raw_id
FROM clean_source cs
JOIN app a
    ON a.app_name_normalized = cs.app_name_normalized
LEFT JOIN category c
    ON c.category_name = cs.category_name
LEFT JOIN app_type t
    ON t.app_type_name = cs.app_type_name
LEFT JOIN content_rating cr
    ON cr.content_rating_name = cs.content_rating_name
LEFT JOIN android_version av
    ON av.android_version_label = cs.android_version_label
ON CONFLICT (raw_id) DO NOTHING;

-- =========================================================
-- QUICK TEST
-- =========================================================
SELECT COUNT(*) AS snapshot_rows
FROM app_snapshot;