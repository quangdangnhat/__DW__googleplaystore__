-- =========================================================
-- FILE: 02_domain_load.sql
-- PROJECT: Google Play Store
-- PURPOSE:
--   Populate reconciled domain/master tables from raw.googleplaystore_import
--   Safe to rerun after 01_reconciled_schema.sql
-- =========================================================

begin;

-- =========================================================
-- CATEGORY
-- =========================================================
insert into reconciled.category (
    category_name,
    category_name_norm
)
select distinct
    trim(r."Category") as category_name,
    lower(trim(r."Category")) as category_name_norm
from raw.googleplaystore_import r
where r."Category" is not null
  and trim(r."Category") <> ''
  and trim(r."Category") <> '1.9'
on conflict (category_name_norm) do nothing;

-- =========================================================
-- APP TYPE
-- =========================================================
insert into reconciled.app_type (
    app_type_name,
    app_type_name_norm
)
select distinct
    trim(r."Type") as app_type_name,
    lower(trim(r."Type")) as app_type_name_norm
from raw.googleplaystore_import r
where r."Type" is not null
  and trim(r."Type") <> ''
  and trim(r."Type") <> '0'
on conflict (app_type_name_norm) do nothing;

-- =========================================================
-- CONTENT RATING
-- =========================================================
insert into reconciled.content_rating (
    content_rating_name,
    content_rating_name_norm
)
select distinct
    trim(r."Content Rating") as content_rating_name,
    lower(trim(r."Content Rating")) as content_rating_name_norm
from raw.googleplaystore_import r
where r."Content Rating" is not null
  and trim(r."Content Rating") <> ''
  and trim(r."Content Rating") <> '0'
on conflict (content_rating_name_norm) do nothing;

-- =========================================================
-- APP
-- =========================================================
insert into reconciled.app (
    app_name,
    app_name_norm
)
select distinct
    trim(r."App") as app_name,
    lower(trim(r."App")) as app_name_norm
from raw.googleplaystore_import r
where r."App" is not null
  and trim(r."App") <> ''
  and trim(r."App") <> 'Life Made WI-Fi Touchscreen Photo Frame'
on conflict (app_name_norm) do nothing;

-- =========================================================
-- QUICK TEST
-- =========================================================
select 'category_rows' as metric, count(*)::text as value
from reconciled.category
union all
select 'app_type_rows' as metric, count(*)::text as value
from reconciled.app_type
union all
select 'content_rating_rows' as metric, count(*)::text as value
from reconciled.content_rating
union all
select 'app_rows' as metric, count(*)::text as value
from reconciled.app;

commit;