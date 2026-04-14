# Google Play Store Data Warehouse Project

## Project goal
This project uses the Google Play Store dataset to design a reconciled database, perform data quality assessment and cleaning, build a data warehouse schema, and support analytical visualization.

## Tech stack
- Supabase (PostgreSQL)
- SQL
- Python / Jupyter
- LaTeX
- VS Code

## Dataset
Source file:
- `data/raw/googleplaystore.csv`

Import-ready file:
- `data/raw/googleplaystore_for_raw_import.csv`

## Current project structure
- `data/`: raw, intermediate, and processed data
- `sql/`: schema, ETL, DQA, cleaning, DW scripts
- `notebooks/`: exploratory analysis and DQA notebooks
- `scripts/`: helper scripts
- `report/`: LaTeX report
- `docs/`: notes, decisions, and progress log

## Execution order
1. Run `sql/01_reconciled_schema.sql`
2. Import `googleplaystore_for_raw_import.csv` into `raw_googleplaystore`
3. Run `sql/02_domain_load.sql`
4. Run `sql/03_app_snapshot_etl.sql`
5. Run `sql/04_genre_etl.sql`
6. Run DQA queries
7. Continue with cleaning, DW design, and ETL

## Reconciled database grain
One row in `app_snapshot` represents one application snapshot from the source dataset.

## Notes
- The raw source is preserved in `raw_googleplaystore`
- `Genres` is modeled as a many-to-many relationship
- One malformed source row is excluded during ETL