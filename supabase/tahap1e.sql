-- =====================================================================
-- Daily Report NKA - MS Allbrand cukup angka per segmen (tanpa tipe)
-- Satu baris per toko, tanggal, brand, segmen. Kolom tipe tidak wajib lagi.
-- Jalankan SETELAH tahap1d.sql. Aman dijalankan ulang. Data lama tetap ada.
-- =====================================================================
alter table public.competitor_sales_detail alter column tipe drop not null;
alter table public.competitor_sales_detail drop constraint if exists competitor_sales_detail_tipe_check;

-- simpan_ms_allbrand (versi tahap1c) sudah menerima p_detail tanpa "tipe":
-- [{"brand_id":1,"segmen":"3to6","unit":2}, ...] -> tipe tersimpan kosong (null).
-- Fungsi dibuat ulang di sini agar unit per brand+segmen digabung jika terkirim lebih dari sekali.
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_ringkas text;
  v_total int;
begin
  if not public.can_write_daily(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. PC hanya bisa input hari ini sebelum 22.00 WIB.';
  end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  insert into public.competitor_sales_detail (store_id, tanggal, brand_id, segmen, tipe, unit, diinput_oleh)
  select p_store, p_tanggal, (d->>'brand_id')::int, d->>'segmen', null, sum((d->>'unit')::int), v_me
    from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) d
   where coalesce((d->>'unit')::int, 0) > 0
   group by (d->>'brand_id')::int, d->>'segmen';
  insert into public.competitor_sales (store_id, tanggal, brand_id, unit, diinput_oleh, updated_at)
  select p_store, p_tanggal, b.id,
         coalesce((select sum(x.unit) from public.competitor_sales_detail x
                    where x.store_id = p_store and x.tanggal = p_tanggal and x.brand_id = b.id), 0),
         v_me, now()
    from public.competitor_brands b
   where b.aktif
  on conflict (store_id, tanggal, brand_id) do update
     set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();

  select string_agg(b.nama || ' ' || c.unit, ', ' order by c.unit desc, b.urutan), coalesce(sum(c.unit), 0)
    into v_ringkas, v_total
    from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
   where c.store_id = p_store and c.tanggal = p_tanggal and c.unit > 0;
  perform public.catat_aktivitas(p_store, v_me, 'ms_allbrand', 'MS Allbrand',
    public.label_aktor(v_me, p_store) || ': brand lain ' || v_total || ' unit'
      || coalesce(' (' || v_ringkas || ')', ' (tidak ada penjualan brand lain)'),
    p_tanggal, null);
end $$;

select 'MS Allbrand tanpa tipe siap' as status;
