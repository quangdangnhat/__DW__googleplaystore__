-- =========================================================
-- FILE: 01_reconciled_schema.sql
-- PURPOSE: Create raw and reconciled schema in PostgreSQL
-- TARGET: Supabase
-- =========================================================

-- Optional reset
-- DROP TABLE IF EXISTS app_snapshot_genre CASCADE;
-- DROP TABLE IF EXISTS app_snapshot CASCADE;
-- DROP TABLE IF EXISTS genre CASCADE;
-- DROP TABLE IF EXISTS android_version CASCADE;
-- DROP TABLE IF EXISTS content_rating CASCADE;
-- DROP TABLE IF EXISTS app_type CASCADE;
-- DROP TABLE IF EXISTS category CASCADE;
-- DROP TABLE IF EXISTS app CASCADE;
-- DROP TABLE IF EXISTS raw_googleplaystore CASCADE;

-- =========================================================
-- 1. RAW TABLE
-- =========================================================

CREATE TABLE IF NOT EXISTS raw_googleplaystore (
    raw_id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_raw              TEXT,
    category_raw         TEXT,
    rating_raw           TEXT,
    reviews_raw          TEXT,
    size_raw             TEXT,
    installs_raw         TEXT,
    type_raw             TEXT,
    price_raw            TEXT,
    content_rating_raw   TEXT,
    genres_raw           TEXT,
    last_updated_raw     TEXT,
    current_ver_raw      TEXT,
    android_ver_raw      TEXT,
    source_file_name     TEXT DEFAULT 'googleplaystore.csv',
    load_timestamp       TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================
-- 2. DOMAIN TABLES
-- =========================================================

CREATE TABLE IF NOT EXISTS app (
    app_id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_name                TEXT NOT NULL,
    app_name_normalized     TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS category (
    category_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name           TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS app_type (
    app_type_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_type_name           TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS content_rating (
    content_rating_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    content_rating_name     TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS android_version (
    android_version_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    android_version_label   TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS genre (
    genre_id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genre_name              TEXT NOT NULL UNIQUE
);

-- =========================================================
-- 3. CENTRAL RECONCILED TABLE
-- Grain: 1 row = 1 app snapshot from source
-- =========================================================

CREATE TABLE IF NOT EXISTS app_snapshot (
    snapshot_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    app_id                  BIGINT NOT NULL,
    category_id             BIGINT,
    app_type_id             BIGINT,
    content_rating_id       BIGINT,
    android_version_id      BIGINT,

    rating                  NUMERIC(3,2),
    reviews_count           BIGINT,
    installs_count          BIGINT,
    price_amount            NUMERIC(10,2),
    size_mb                 NUMERIC(10,2),

    size_label_raw          TEXT,
    current_version         TEXT,
    last_updated_date       DATE,

    raw_id                  BIGINT UNIQUE,
    created_at              TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_app_snapshot_app
        FOREIGN KEY (app_id) REFERENCES app(app_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_app_snapshot_category
        FOREIGN KEY (category_id) REFERENCES category(category_id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT fk_app_snapshot_app_type
        FOREIGN KEY (app_type_id) REFERENCES app_type(app_type_id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT fk_app_snapshot_content_rating
        FOREIGN KEY (content_rating_id) REFERENCES content_rating(content_rating_id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT fk_app_snapshot_android_version
        FOREIGN KEY (android_version_id) REFERENCES android_version(android_version_id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT fk_app_snapshot_raw
        FOREIGN KEY (raw_id) REFERENCES raw_googleplaystore(raw_id)
        ON UPDATE CASCADE ON DELETE SET NULL,

    CONSTRAINT chk_rating_range
        CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),

    CONSTRAINT chk_reviews_nonnegative
        CHECK (reviews_count IS NULL OR reviews_count >= 0),

    CONSTRAINT chk_installs_nonnegative
        CHECK (installs_count IS NULL OR installs_count >= 0),

    CONSTRAINT chk_price_nonnegative
        CHECK (price_amount IS NULL OR price_amount >= 0),

    CONSTRAINT chk_size_nonnegative
        CHECK (size_mb IS NULL OR size_mb >= 0)
);

-- =========================================================
-- 4. MANY-TO-MANY TABLE FOR GENRES
-- =========================================================

CREATE TABLE IF NOT EXISTS app_snapshot_genre (
    snapshot_id             BIGINT NOT NULL,
    genre_id                BIGINT NOT NULL,

    PRIMARY KEY (snapshot_id, genre_id),

    CONSTRAINT fk_app_snapshot_genre_snapshot
        FOREIGN KEY (snapshot_id) REFERENCES app_snapshot(snapshot_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_app_snapshot_genre_genre
        FOREIGN KEY (genre_id) REFERENCES genre(genre_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- =========================================================
-- 5. INDEXES
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_app_app_name
    ON app(app_name);

CREATE INDEX IF NOT EXISTS idx_app_app_name_normalized
    ON app(app_name_normalized);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_app_id
    ON app_snapshot(app_id);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_category_id
    ON app_snapshot(category_id);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_type_id
    ON app_snapshot(app_type_id);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_content_rating_id
    ON app_snapshot(content_rating_id);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_android_version_id
    ON app_snapshot(android_version_id);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_last_updated_date
    ON app_snapshot(last_updated_date);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_rating
    ON app_snapshot(rating);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_installs_count
    ON app_snapshot(installs_count);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_reviews_count
    ON app_snapshot(reviews_count);

CREATE INDEX IF NOT EXISTS idx_app_snapshot_genre_genre_id
    ON app_snapshot_genre(genre_id);