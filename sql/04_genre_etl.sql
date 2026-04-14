-- =========================================================
-- FILE: 04_genre_etl.sql
-- PURPOSE: Populate genre and app_snapshot_genre
-- =========================================================

-- =========================================================
-- GENRE
-- =========================================================
INSERT INTO genre (genre_name)
SELECT DISTINCT TRIM(g.genre_name)
FROM (
    SELECT REGEXP_SPLIT_TO_TABLE(genres_raw, ';') AS genre_name
    FROM raw_googleplaystore
    WHERE genres_raw IS NOT NULL
      AND TRIM(genres_raw) <> ''
      AND COALESCE(TRIM(category_raw), '') <> '1.9'
) g
WHERE TRIM(g.genre_name) <> ''
ON CONFLICT (genre_name) DO NOTHING;

-- =========================================================
-- BRIDGE TABLE
-- =========================================================
INSERT INTO app_snapshot_genre (snapshot_id, genre_id)
SELECT DISTINCT
    s.snapshot_id,
    g.genre_id
FROM raw_googleplaystore r
JOIN app_snapshot s
    ON s.raw_id = r.raw_id
CROSS JOIN LATERAL REGEXP_SPLIT_TO_TABLE(r.genres_raw, ';') AS genre_part
JOIN genre g
    ON g.genre_name = TRIM(genre_part)
WHERE r.genres_raw IS NOT NULL
  AND TRIM(r.genres_raw) <> ''
  AND COALESCE(TRIM(r.category_raw), '') <> '1.9'
ON CONFLICT (snapshot_id, genre_id) DO NOTHING;

-- =========================================================
-- QUICK TEST
-- =========================================================
SELECT 'genre_rows' AS metric, COUNT(*)::TEXT AS value FROM genre
UNION ALL
SELECT 'genre_links' AS metric, COUNT(*)::TEXT AS value FROM app_snapshot_genre;