# Google Play Store Data Warehouse 🏛️📊

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Supabase-3ECF8E?style=flat-square&logo=postgresql&logoColor=white)
![Data Warehouse](https://img.shields.io/badge/Data%20Warehouse-Star%20Schema-8A2BE2?style=flat-square)


> Transforming Google Play Store raw data into a verified, auditable, OLAP-ready data warehouse.

This project builds a data warehouse for the Google Play Store dataset. It starts from the original CSV, loads it into a raw landing table, transforms it into a reconciled PostgreSQL schema, performs baseline data quality assessment, creates a conservative cleaning and audit layer, and finally loads a dimensional star schema for OLAP-style analysis.

The analytical grain is **one app snapshot**: one row in `reconciled.app_snapshot` / `dw.fact_app_snapshot` represents one loaded Google Play Store source row for one application snapshot.

---

## 🧰 Tech Stack

- **Supabase / PostgreSQL**
- **Python**, optional for analysis/report support
- **LaTeX**, for report writing

---

## 📦 Dataset

Source file:

- `data/raw/googleplaystore.csv`

Import target table:

- `raw.googleplaystore_import`

> **Import note:** `01_reconciled_schema.sql` creates the raw landing table with column names matching the original CSV headers exactly, so the CSV should be imported into `raw.googleplaystore_import` after running that script.

---

## 🗂️ Current Project Structure

- `data/`: raw, intermediate, and processed data files
- `sql/`: schema, ETL, DQA, cleaning, DW, and verification scripts
- `report/`: LaTeX project report
- `docs/`: notes, decisions, progress log, and supporting documentation

---

## 🧭 SQL Pipeline Overview

### 🧱 Phase 1 — Reconciled Schema and Source ETL

| Order | File | Purpose |
|---:|---|---|
| 1 | `sql/01_reconciled_schema.sql` | Resets and creates `raw` and `reconciled` schemas. Creates `raw.googleplaystore_import`, reconciled domain tables, `reconciled.app`, `reconciled.app_snapshot`, and `reconciled.app_snapshot_genre`. |
| 2 | CSV import | Import `googleplaystore.csv` into `raw.googleplaystore_import`. |
| 3 | `sql/02_domain_load.sql` | Loads normalized domain/master data: category, app type, content rating, and app. Excludes known malformed shifted values such as `Category = '1.9'`. |
| 4 | `sql/03_app_snapshot_etl.sql` | Transforms raw text fields into typed snapshot measures and descriptors. Loads `reconciled.app_snapshot`. Excludes the malformed shifted source row. |
| 5 | `sql/04_genre_etl.sql` | Extracts valid genres from the multi-valued `Genres` source column and loads the many-to-many bridge `reconciled.app_snapshot_genre`. |
| 6 | `sql/verifyPhase1.sql` | Verification script for Phase 1 counts, malformed row exclusion, FK nulls, measure validity, genre bridge integrity, and expected Phase 1 evidence. |

### 🧼 Phase 2 — DQA, Cleaning, and DW Loading

| Order | File | Purpose |
|---:|---|---|
| 7 | `sql/05_dqa_queries.sql` | Creates `dq` views for baseline data quality assessment before cleaning. Covers completeness, uniqueness, validity, consistency, timeliness, and accuracy notes. Does not modify source data. |
| 8 | `sql/06_cleaning_and_audit.sql` | Creates `clean` schema, `clean.app_snapshot_clean`, `clean.app_snapshot_genre_clean`, and `clean.cleaning_audit_log`. Uses conservative cleaning: preserve meaningful NULLs, add flags, and log decisions. |
| 9 | `sql/07_dw_star_schema.sql` | Creates the `dw` star schema: dimensions, fact table, genre bridge with weights, constraints, indexes, and analysis views. |
| 10 | `sql/08_dw_etl.sql` | Loads dimensions, fact, date dimension, genre bridge, and DW summary/integrity views from the clean/reconciled layer. |
| 11 | `sql/verifyPhase2.sql` | Verification script for Phase 2 counts, cleaning flags, audit rows, bridge weights, FK integrity, weighted genre aggregation, and expected empty failure sets. |

---

## 🚀 Full Execution Order

Run these steps in Supabase/PostgreSQL:

1. Run `sql/01_reconciled_schema.sql`.
2. Import `data/raw/googleplaystore.csv` into `raw.googleplaystore_import`.
3. Run `sql/02_domain_load.sql`.
4. Run `sql/03_app_snapshot_etl.sql`.
5. Run `sql/04_genre_etl.sql`.
6. Run `sql/verifyPhase1.sql` and save outputs as Phase 1 evidence.
7. Run `sql/05_dqa_queries.sql`.
8. Run `sql/06_cleaning_and_audit.sql`.
9. Run `sql/07_dw_star_schema.sql`.
10. Run `sql/08_dw_etl.sql`.
11. Run `sql/verifyPhase2.sql` and save outputs as Phase 2 evidence.

---

## 🏗️ Database Layers

### 🥫 Raw Layer

**Schema:** `raw`

Main table:

- `raw.googleplaystore_import`

Purpose:

- Preserve the original CSV values as text.
- Keep source headers unchanged for easier Supabase CSV import.
- Preserve the malformed shifted row in raw data for lineage and auditability.

### 🔁 Reconciled Layer

**Schema:** `reconciled`

Main tables:

- `reconciled.app`
- `reconciled.category`
- `reconciled.app_type`
- `reconciled.content_rating`
- `reconciled.genre`
- `reconciled.app_snapshot`
- `reconciled.app_snapshot_genre`

Purpose:

- Standardize and type source values.
- Separate descriptive entities into normalized domain/master tables.
- Store typed numeric measures such as `rating`, `reviews_count`, `size_bytes`, `installs_count`, and `price_usd`.
- Represent `Genres` as a many-to-many relationship through `reconciled.app_snapshot_genre`.

### 🔍 Data Quality Layer

**Schema:** `dq`

Main views:

- `dq.v_reconciliation_counts`
- `dq.v_app_snapshot_enriched`
- `dq.v_dqa_baseline_scorecard`
- issue-detail views for missing values, validity checks, consistency checks, timeliness, and genre analysis

Purpose:

- Assess data quality before cleaning.
- Produce evidence for completeness, uniqueness, validity, consistency, timeliness, and accuracy limitations.
- Identify rows that need flags or review.

### 🧽 Clean / Audit Layer

**Schema:** `clean`

Main tables/views:

- `clean.app_snapshot_clean`
- `clean.app_snapshot_genre_clean`
- `clean.cleaning_audit_log`
- cleaning summary and after-cleaning DQA views

Cleaning strategy:

- Do not impute analytical measures such as `rating` and `size_bytes`.
- Preserve meaningful NULLs.
- Add explicit flags such as `rating_missing_flag`, `size_missing_flag`, `app_type_missing_flag`, `current_version_missing_flag`, and `multiple_genre_flag`.
- Add `dq_status` values: `OK`, `FLAGGED_OK`, `ERROR_REVIEW`.
- Log cleaning and flagging decisions in `clean.cleaning_audit_log`.
- Add bridge weights for safe genre analysis.

### ⭐ Data Warehouse Layer

**Schema:** `dw`

Dimensions:

- `dw.dim_app`
- `dw.dim_category`
- `dw.dim_app_type`
- `dw.dim_content_rating`
- `dw.dim_last_updated_date`
- `dw.dim_genre`

Fact and bridge:

- `dw.fact_app_snapshot`
- `dw.bridge_app_snapshot_genre`

Purpose:

- Implement the Phase 1 star schema.
- Support OLAP-style analysis by app, category, app type, content rating, last updated date, and genre.
- Preserve Phase 2 DQ flags in the fact table so BI users can filter or explain missing/flagged values.
- Use weighted genre bridge rows to avoid double counting when analyzing by genre.

---

## 🎯 Reconciled and DW Grain

The central grain is:

> One row = one observed Google Play Store app snapshot loaded from one valid source row.

In Phase 1:

- Raw rows: `10841`
- Reconciled app snapshots: `10840`
- Excluded malformed source rows: `1`

The excluded row is the shifted malformed record for `Life Made WI-Fi Touchscreen Photo Frame`. It remains preserved in `raw.googleplaystore_import` but is not loaded into `reconciled.app_snapshot`.

---

## ✅ Key Expected Counts

These counts are based on the provided Google Play Store CSV and are used by the verification scripts.

### Phase 1 Expected Counts

| Object / metric | Expected count |
|---|---:|
| `raw.googleplaystore_import` | 10841 |
| `reconciled.category` | 33 |
| `reconciled.app_type` | 2 |
| `reconciled.content_rating` | 6 |
| `reconciled.app` | 9638 |
| `reconciled.app_snapshot` | 10840 |
| excluded raw rows | 1 |
| `reconciled.genre` | 53 |
| `reconciled.app_snapshot_genre` | 11288 |
| snapshots with genre | 10840 |
| orphan bridge rows | 0 |

### Phase 2 Expected Counts

| Object / metric | Expected count |
|---|---:|
| `clean.app_snapshot_clean` | 10840 |
| `clean.app_snapshot_genre_clean` | 11288 |
| `dw.fact_app_snapshot` | 10840 |
| `dw.bridge_app_snapshot_genre` | 11288 |
| `dw.dim_app` | 9638 |
| `dw.dim_category` | 33 |
| `dw.dim_app_type` | 3 |
| `dw.dim_content_rating` | 6 |
| `dw.dim_genre` | 53 |

> `dw.dim_app_type` has 3 rows because the DW adds a technical `Unknown` member to handle the one snapshot with missing app type while avoiding NULL foreign keys in the fact table.

---

## 🛡️ Important Data Quality Decisions

- Rating NULLs are preserved because missing ratings are analytically meaningful and should not be blindly imputed.
- Size NULLs are preserved because source values such as `Varies with device` are meaningful, not simple errors.
- Missing app type is flagged and mapped to `Unknown` only in the DW dimension/fact loading step.
- The raw source is never overwritten by cleaning scripts.
- Accuracy is documented as not fully scored because there is no external reference truth for the Google Play Store values.
- Genre is many-to-many, so direct joins can double count snapshots and measures. Use the weighted bridge or provided analysis views for genre-based KPIs.

---

## 🌉 Genre Bridge and Weighted Analysis

The source `Genres` field can contain multiple genres separated by `;`. The project models this using bridge tables:

- `reconciled.app_snapshot_genre`
- `clean.app_snapshot_genre_clean`
- `dw.bridge_app_snapshot_genre`

In the clean and DW layers, each bridge row includes a `weight`:

- snapshot with 1 genre: weight = `1.0`
- snapshot with 2 genres: weight = `0.5` per genre

This prevents double counting in genre analysis. For genre-level KPIs, use the provided weighted genre views instead of directly summing fact measures after joining to the genre bridge.

---

## 🧪 Verification Scripts

Use these scripts to capture evidence for the report:

- `sql/verifyPhase1.sql`: run after files `01` to `04`.
- `sql/verifyPhase2.sql`: run after files `05` to `08`.

`verifyPhase2.sql` also includes expected empty result-set checks. These should return 0 rows:

- clean bridge weight errors
- DW bridge weight errors
- after-cleaning scorecard non-green metrics
- DW integrity failures

---

## 📝 Notes

- Scripts are designed to be rerunnable from a clean state.
- `01_reconciled_schema.sql` drops and recreates `raw` and `reconciled`.
- `06_cleaning_and_audit.sql` drops and recreates only `clean`.
- `07_dw_star_schema.sql` drops and recreates only `dw`.
- `08_dw_etl.sql` resets DW data before loading.
- The raw table name is `raw.googleplaystore_import`, not `raw_googleplaystore`.
