-- =========================================================
-- 03_app_snapshot_etl.sql
-- Project: Google Play Store
-- Purpose:
--   Transform raw rows into typed reconciled snapshot rows.
-- =========================================================
begin;

delete from reconciled.app_snapshot;

with
  src as (
    select
      r.raw_id,
      r."App",
      r."Category",
      r."Rating",
      r."Reviews",
      r."Size",
      r."Installs",
      r."Type",
      r."Price",
      r."Content Rating",
      r."Last Updated",
      r."Current Ver",
      r."Android Ver"
    from
      raw.googleplaystore_import r
  ),
  typed as (
    select
      s.raw_id,
      s."App" as app_raw,
      s."Category" as category_raw,
      s."Type" as type_raw,
      s."Content Rating" as content_rating_raw,
      case
        when s."Rating" is null
        or trim(s."Rating") = '' then null
        when trim(s."Rating") ~ '^[0-9]+(\.[0-9]+)?$' then case
          when trim(s."Rating")::numeric between 0 and 5  then trim(s."Rating")::numeric(3, 2)
          else null
        end
        else null
      end as rating,
      case
        when s."Reviews" is null
        or trim(s."Reviews") = '' then null
        when trim(s."Reviews") ~ '^[0-9]+$' then trim(s."Reviews")::bigint
        else null
      end as reviews_count,
      case
        when s."Size" is null
        or trim(s."Size") = '' then null
        when lower(trim(s."Size")) = 'varies with device' then null
        when trim(s."Size") ~ '^[0-9]+(\.[0-9]+)?[Mm]$' then round(
          replace(lower(trim(s."Size")), 'm', '')::numeric * 1024 * 1024
        )::bigint
        when trim(s."Size") ~ '^[0-9]+(\.[0-9]+)?[Kk]$' then round(
          replace(lower(trim(s."Size")), 'k', '')::numeric * 1024
        )::bigint
        else null
      end as size_bytes,
      case
        when s."Installs" is null
        or trim(s."Installs") = '' then null
        when nullif(
          regexp_replace(trim(s."Installs"), '[^0-9]', '', 'g'),
          ''
        ) is not null then nullif(
          regexp_replace(trim(s."Installs"), '[^0-9]', '', 'g'),
          ''
        )::bigint
        else null
      end as installs_count,
      case
        when s."Price" is null
        or trim(s."Price") = '' then null
        when nullif(
          regexp_replace(trim(s."Price"), '[^0-9\.]', '', 'g'),
          ''
        ) is not null then nullif(
          regexp_replace(trim(s."Price"), '[^0-9\.]', '', 'g'),
          ''
        )::numeric(10, 2)
        else null
      end as price_usd,
      case
        when s."Last Updated" is null
        or trim(s."Last Updated") = '' then null
        when trim(s."Last Updated") ~ '^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2}$' then to_date(trim(s."Last Updated"), 'DD-Mon-YY')
        else null
      end as last_updated_date,
      nullif(trim(s."Current Ver"), '') as current_version,
      nullif(trim(s."Android Ver"), '') as android_version_text
    from
      src s
  )
insert into
  reconciled.app_snapshot (
    raw_id,
    app_id,
    category_id,
    app_type_id,
    content_rating_id,
    rating,
    reviews_count,
    size_bytes,
    installs_count,
    price_usd,
    last_updated_date,
    current_version,
    android_version_text,
    inserted_at
  )
select
  t.raw_id,
  a.app_id,
  c.category_id,
  atp.app_type_id,
  cr.content_rating_id,
  t.rating,
  t.reviews_count,
  t.size_bytes,
  t.installs_count,
  t.price_usd,
  t.last_updated_date,
  t.current_version,
  t.android_version_text,
  now()
from
  typed t
  join reconciled.app a on a.app_name_norm = lower(trim(t.app_raw))
  left join reconciled.category c on c.category_name_norm = lower(trim(t.category_raw))
  left join reconciled.app_type atp on atp.app_type_name_norm = lower(trim(t.type_raw))
  left join reconciled.content_rating cr on cr.content_rating_name_norm = lower(trim(t.content_rating_raw));

commit;