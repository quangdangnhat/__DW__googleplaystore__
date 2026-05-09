-- 1. Verify raw import

select count(*) as raw_rows
from raw.googleplaystore_import;
-- Expected: 10841

-- Check bad shifted row vẫn tồn tại ở raw là bình thường:
select raw_id, "App", "Category", "Rating", "Reviews", "Installs", "Type", "Genres"
from raw.googleplaystore_import
where "Category" = '1.9';
-- Expected: 1 row, chính là Life Made WI-Fi Touchscreen Photo Frame. Raw giữ nguyên dữ liệu gốc nên row này không cần xóa ở raw.


-- 2. Verify sau file 2 — domain tables

-- Bạn đã fix app_type_rows = 2, vậy chạy lại block này:
select 'category_rows' as metric, count(*)::text as value
from reconciled.category
union all
select 'app_type_rows', count(*)::text
from reconciled.app_type
union all
select 'content_rating_rows', count(*)::text
from reconciled.content_rating
union all
select 'app_rows', count(*)::text
from reconciled.app;
-- Expected:
-- category_rows              33
-- app_type_rows               2
-- content_rating_rows         6
-- app_rows                 9638

-- Verify không còn dirty domain values:
select *
from reconciled.category
where category_name_norm in ('1.9', 'nan', 'null', '0');

select *
from reconciled.app_type
where app_type_name_norm not in ('free', 'paid');

select *
from reconciled.app
where app_name_norm like 'life made wi-fi%';
-- Expected: cả 3 query đều trả về 0 rows.


-- 3. Verify sau file 3 — app_snapshot

-- Sau khi chạy 03_app_snapshot_etl.sql, chạy:
select count(*) as app_snapshot_rows
from reconciled.app_snapshot;
-- Expected: 10840
-- Lý do: raw có 10841 rows, nhưng 1 shifted invalid row bị loại khỏi reconciled snapshot.

-- Kiểm tra đúng row bị loại:
select r.raw_id, r."App", r."Category", r."Rating", r."Installs", r."Type"
from raw.googleplaystore_import r
left join reconciled.app_snapshot s
    on s.raw_id = r.raw_id
where s.raw_id is null;
-- Expected: chỉ 1 row, Life Made WI-Fi Touchscreen Photo Frame.

-- Check foreign key nulls:
select
    count(*) filter (where app_id is null) as null_app_id,
    count(*) filter (where category_id is null) as null_category_id,
    count(*) filter (where app_type_id is null) as null_app_type_id,
    count(*) filter (where content_rating_id is null) as null_content_rating_id
from reconciled.app_snapshot;

-- Expected hợp lý:
-- null_app_id              0
-- null_category_id         0
-- null_app_type_id         1
-- null_content_rating_id   0
-- null_app_type_id = 1 là acceptable ở Phase 1 vì raw có app Command & Conquer: Rivals với missing Type. Đây sẽ là input tốt cho Phase 2 DQA.

-- Check measure validity:
select
    count(*) filter (where rating is not null and (rating < 0 or rating > 5)) as bad_rating,
    count(*) filter (where reviews_count < 0) as bad_reviews,
    count(*) filter (where size_bytes < 0) as bad_size,
    count(*) filter (where installs_count < 0) as bad_installs,
    count(*) filter (where price_usd < 0) as bad_price,
    count(*) filter (where last_updated_date is null) as null_last_updated_date
from reconciled.app_snapshot;

-- Expected:
-- bad_rating              0
-- bad_reviews             0
-- bad_size                0
-- bad_installs            0
-- bad_price               0
-- null_last_updated_date  0


-- 4. Verify sau file 4 — Genre bridge

-- Sau khi chạy 04_genre_etl.sql:
select 'genre_rows' as metric, count(*)::text as value
from reconciled.genre
union all
select 'app_snapshot_genre_rows', count(*)::text
from reconciled.app_snapshot_genre
union all
select 'snapshots_with_genre', count(distinct snapshot_id)::text
from reconciled.app_snapshot_genre;
-- Expected:
-- genre_rows                  53
-- app_snapshot_genre_rows  11288
-- snapshots_with_genre     10840

-- Check no orphan bridge rows:
select count(*) as orphan_bridge_rows
from reconciled.app_snapshot_genre sg
left join reconciled.app_snapshot s
    on s.snapshot_id = sg.snapshot_id
left join reconciled.genre g
    on g.genre_id = sg.genre_id
where s.snapshot_id is null
   or g.genre_id is null;

-- Expected: 0

-- Check bad genre không lọt vào:
select *
from reconciled.genre
where genre_name_norm ~ '^[0-9]{1,2}-[a-z]{3}-[0-9]{2}$'
   or genre_name_norm in ('nan', 'null', '');
-- Expected: 0 rows.


-- 5. Ghi lại evidence trước Phase 2
-- raw_rows = 10841
-- category_rows = 33
-- app_type_rows = 2
-- content_rating_rows = 6
-- app_rows = 9638
-- app_snapshot_rows = 10840
-- excluded_raw_rows = 1
-- genre_rows = 53
-- app_snapshot_genre_rows = 11288
-- snapshots_with_genre = 10840
-- orphan_bridge_rows = 0