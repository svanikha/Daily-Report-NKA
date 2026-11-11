-- =====================================================================
-- Daily Report NKA - Tahap 2c: MS Allbrand per tanggal, bisa diedit kapan saja di bulan berjalan
--   - Data tiap tanggal tetap tersimpan sampai dihapus.
--   - PC (tokonya), TL & Trainer (areanya) boleh mengisi / mengedit tanggal 1 s.d. hari ini
--     di bulan berjalan, walaupun tanggalnya sudah lewat dan laporan sudah terkirim.
--   - PIC NKA boleh semua tanggal (bukan tanggal yang akan datang).
--   - Hapus MS Allbrand satu tanggal.
-- Jalankan SETELAH tahap2b.sql. Aman dijalankan ulang.
-- =====================================================================

create or replace function public.can_write_ms(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select p_tanggal <= public.today_wib()
     and (
       public.is_pic()
       or (date_trunc('month', p_tanggal) = date_trunc('month', public.today_wib()::timestamp)
           and ((public.my_role() = 'pc' and p_store = public.my_store_id())
                or (public.my_role() in ('tl', 'trainer') and public.store_area(p_store) = public.my_area_id())))
     )
$$;

-- Simpan MS Allbrand satu tanggal (menggantikan isian tanggal itu saja; tanggal lain tidak tersentuh).
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb, p_notif boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_ringkas text;
  v_total int;
begin
  if not public.can_write_ms(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. MS Allbrand hanya bisa diisi untuk tanggal 1 s.d. hari ini di bulan berjalan.';
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

  if not coalesce(p_notif, true) then return; end if;

  select string_agg(b.nama || ' ' || c.unit, ', ' order by c.unit desc, b.urutan), coalesce(sum(c.unit), 0)
    into v_ringkas, v_total
    from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
   where c.store_id = p_store and c.tanggal = p_tanggal and c.unit > 0;
  perform public.catat_aktivitas(p_store, v_me, 'ms_allbrand', 'MS Allbrand',
    public.label_aktor(v_me, p_store) || ': brand lain ' || v_total || ' unit'
      || case when p_tanggal = public.today_wib() then ' hari ini' else ' tgl ' || to_char(p_tanggal, 'DD/MM') end
      || coalesce(' (' || v_ringkas || ')', ' (tidak ada penjualan brand lain)'),
    p_tanggal, null);
end $$;

-- Hapus MS Allbrand satu tanggal (tanggal itu kembali "belum diisi").
create or replace function public.hapus_ms_allbrand(p_store int, p_tanggal date) returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.my_profile_id();
begin
  if not public.can_write_ms(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan menghapus MS Allbrand tanggal ini.';
  end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  delete from public.competitor_sales where store_id = p_store and tanggal = p_tanggal;
  perform public.catat_aktivitas(p_store, v_me, 'ms_allbrand', 'MS Allbrand dihapus',
    public.label_aktor(v_me, p_store) || ' menghapus MS Allbrand tgl ' || to_char(p_tanggal, 'DD/MM'),
    p_tanggal, null);
end $$;

select 'MS Allbrand per tanggal siap' as status,
       public.can_write_ms(1, public.today_wib()) is not null as fungsi_ada;
