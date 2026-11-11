-- =====================================================================
-- Daily Report NKA - Tahap 2d: daftar & urutan brand MS Allbrand
--   Vivo, Samsung, Xiaomi, Realme, Infinix, Tecno, Apple, Itel, Huawei, Others
--   Honor dan Advan dinonaktifkan (data lama tetap tersimpan). "Lainnya" menjadi "Others".
--   Apple hanya segmen 6 jt up (dijaga di aplikasi dan di server).
-- Jalankan SETELAH tahap2c.sql. Aman dijalankan ulang.
-- =====================================================================

-- "Lainnya" -> "Others" (data lama ikut menjadi Others)
update public.competitor_brands set nama = 'Others'
 where lower(nama) = 'lainnya'
   and not exists (select 1 from public.competitor_brands where nama = 'Others');

insert into public.competitor_brands (nama, urutan)
select 'Others', 10 where not exists (select 1 from public.competitor_brands where nama = 'Others');

-- Urutan & penulisan nama
update public.competitor_brands b
   set nama = v.nama, urutan = v.urutan, aktif = true
  from (values ('vivo', 'Vivo', 1), ('samsung', 'Samsung', 2), ('xiaomi', 'Xiaomi', 3), ('realme', 'Realme', 4),
               ('infinix', 'Infinix', 5), ('tecno', 'Tecno', 6), ('apple', 'Apple', 7), ('itel', 'Itel', 8),
               ('huawei', 'Huawei', 9), ('others', 'Others', 10)) v(kunci, nama, urutan)
 where lower(b.nama) = v.kunci;

-- Brand lain (Honor, Advan, dll.) disembunyikan dari input. Datanya tidak dihapus.
update public.competitor_brands set aktif = false
 where lower(nama) not in ('vivo', 'samsung', 'xiaomi', 'realme', 'infinix', 'tecno', 'apple', 'itel', 'huawei', 'others');

-- Apple hanya boleh segmen 6 jt up
create or replace function public.cek_segmen_brand() returns trigger
language plpgsql as $$
begin
  if new.segmen <> 'gt6' and exists (select 1 from public.competitor_brands where id = new.brand_id and lower(nama) = 'apple') then
    raise exception 'Apple hanya untuk segmen 6 jt up';
  end if;
  return new;
end $$;
drop trigger if exists trg_cek_segmen_brand on public.competitor_sales_detail;
create trigger trg_cek_segmen_brand before insert or update on public.competitor_sales_detail
  for each row execute function public.cek_segmen_brand();

select nama, urutan, aktif from public.competitor_brands order by aktif desc, urutan;
