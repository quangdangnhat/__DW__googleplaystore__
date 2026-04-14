-- =========================================================
-- FILE: 02_domain_load.sql
-- PURPOSE: Populate domain tables from raw_googleplaystore
-- =========================================================

-- Ensure app_name_normalized is unique
DO $$
BEGIN
    ALTER TABLE app
    ADD CONSTRAINT uq_app_app_name_normalized UNIQUE (app_name_normalized);
EXCEPTION
    WHEN duplicate_object THEN
        NULL;
END $$;

-- =========================================================
-- CATEGORY
-- =========================================================
INSERT INTO category (category_name)
SELECT DISTINCT TRIM(category_raw)
FROM raw_googleplaystore
WHERE category_raw IS NOT NULL
  AND TRIM(category_raw) <> ''
  AND TRIM(category_raw) <> '1.9'
ON CONFLICT (category_name) DO NOTHING;

-- =========================================================
-- APP TYPE
-- =========================================================
INSERT INTO app_type (app_type_name)
SELECT DISTINCT TRIM(type_raw)
FROM raw_googleplaystore
WHERE type_raw IS NOT NULL
  AND TRIM(type_raw) <> ''
ON CONFLICT (app_type_name) DO NOTHING;

-- =========================================================
-- CONTENT RATING
-- =========================================================
INSERT INTO content_rating (content_rating_name)
SELECT DISTINCT TRIM(content_rating_raw)
FROM raw_googleplaystore
WHERE content_rating_raw IS NOT NULL
  AND TRIM(content_rating_raw) <> ''
ON CONFLICT (content_rating_name) DO NOTHING;

-- =========================================================
-- ANDROID VERSION
-- =========================================================
INSERT INTO android_version (android_version_label)
SELECT DISTINCT TRIM(android_ver_raw)
FROM raw_googleplaystore
WHERE android_ver_raw IS NOT NULL
  AND TRIM(android_ver_raw) <> ''
ON CONFLICT (android_version_label) DO NOTHING;

-- =========================================================
-- APP
-- =========================================================
INSERT INTO app (app_name, app_name_normalized)
SELECT DISTINCT
    TRIM(app_raw) AS app_name,
    LOWER(TRIM(app_raw)) AS app_name_normalized
FROM raw_googleplaystore
WHERE app_raw IS NOT NULL
  AND TRIM(app_raw) <> ''
ON CONFLICT (app_name_normalized) DO NOTHING;

-- =========================================================
-- QUICK TEST
-- =========================================================
SELECT 'category_rows' AS metric, COUNT(*)::TEXT AS value FROM category
UNION ALL
SELECT 'app_type_rows' AS metric, COUNT(*)::TEXT AS value FROM app_type
UNION ALL
SELECT 'content_rating_rows' AS metric, COUNT(*)::TEXT AS value FROM content_rating
UNION ALL
SELECT 'android_version_rows' AS metric, COUNT(*)::TEXT AS value FROM android_version
UNION ALL
SELECT 'app_rows' AS metric, COUNT(*)::TEXT AS value FROM app;