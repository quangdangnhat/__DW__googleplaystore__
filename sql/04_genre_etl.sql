-- =========================================================
-- 04_genre_etl.sql
-- Project: Google Play Store
-- Purpose:
--   1) Extract valid distinct genres from raw data
--   2) Load reconciled.genre
--   3) Build reconciled.app_snapshot_genre bridge table
-- Notes:
--   - Handles multi-valued Genres separated by ';'
--   - Excludes invalid genre values that match date patterns
--   - Safe to rerun
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 0) RERUN SAFETY
-- ---------------------------------------------------------
delete from reconciled.app_snapshot_genre;
delete from reconciled.genre;

-- ---------------------------------------------------------
-- 1) LOAD DISTINCT VALID GENRES
-- ---------------------------------------------------------
insert into reconciled.genre (
    genre_name,
    genre_name_norm
)
select distinct
    trim(g_raw) as genre_name,
    lower(trim(g_raw)) as genre_name_norm
from raw.googleplaystore_import r
cross join unnest(string_to_array(r."Genres", ';')) as g_raw
where r."Genres" is not null
  and trim(r."Genres") <> ''
  and trim(g_raw) <> ''
  and trim(g_raw) !~ '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}$'
on conflict (genre_name_norm) do nothing;

-- ---------------------------------------------------------
-- 2) LOAD SNAPSHOT <-> GENRE BRIDGE
-- ---------------------------------------------------------
insert into reconciled.app_snapshot_genre (
    snapshot_id,
    genre_id,
    inserted_at
)
select distinct
    s.snapshot_id,
    g.genre_id,
    now()
from raw.googleplaystore_import r
join reconciled.app_snapshot s
    on s.raw_id = r.raw_id
cross join unnest(string_to_array(r."Genres", ';')) as g_raw
join reconciled.genre g
    on g.genre_name_norm = lower(trim(g_raw))
where r."Genres" is not null
  and trim(r."Genres") <> ''
  and trim(g_raw) <> ''
  and trim(g_raw) !~ '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}$'
on conflict (snapshot_id, genre_id) do nothing;

commit;