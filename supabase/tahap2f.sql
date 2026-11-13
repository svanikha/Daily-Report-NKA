-- =====================================================================
-- Daily Report NKA - Tahap 2f
--   1. PC membalas pengingat atasan dengan "Siap 👍" (tanda pesan tersampaikan)
--   2. Ringkasan sell out (hari ini, bulan ini, target) untuk dashboard, bisa per toko / semua toko
--   3. Kontribusi penjualan per series & tipe (bulan berjalan)
-- Hanya MENAMBAH fungsi/kolom: aplikasi versi lama tetap berjalan normal.
-- Jalankan SETELAH tahap2e.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. BALASAN PENGINGAT
-- ---------------------------------------------------------------------
alter table public.pengingat add column if not exists respon text;
alter table public.pengingat add column if not exists respon_pada timestamptz;

alter table public.aktivitas drop constraint if exists aktivitas_jenis_check;
alter table public.aktivitas add constraint aktivitas_jenis_check check (jenis in (
  'penjualan_hp', 'penjualan_iot', 'hapus_penjualan', 'nosell', 'stok', 'ms_allbrand', 'display',
  'laporan', 'tidak_lapor', 'istirahat_mulai', 'istirahat_selesai', 'istirahat_telat', 'sosmed', 'leasing',
  'pengingat'));

-- PC membalas satu pengingat (p_id) atau semua yang belum dibalas (p_id null) dengan "Siap".
-- Atasan menerima notifikasi bahwa pesan sudah sampai.
create or replace function public.respon_pengingat(p_id uuid default null, p_respon text default 'Siap') returns int
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  r record;
  n int := 0;
begin
  for r in
    select g.*, coalesce(d.nama, 'atasan') || case d.role when 'tl' then ' (TL)' when 'trainer' then ' (Trainer)'
                                                         else ' (PIC)' end as dari_label
      from public.pengingat g left join public.profiles d on d.id = g.dari
     where g.pc_id = v_me and g.respon is null and (p_id is null or g.id = p_id)
     order by g.created_at
  loop
    update public.pengingat set respon = coalesce(nullif(trim(p_respon), ''), 'Siap'), respon_pada = now(),
                                dibaca_pada = coalesce(dibaca_pada, now())
     where id = r.id;
    perform public.catat_aktivitas(r.store_id, v_me, 'pengingat', 'PC: Siap 👍',
      public.label_aktor(v_me, r.store_id) || ' membalas "' || coalesce(nullif(trim(p_respon), ''), 'Siap') || ' 👍" '
        || 'untuk pengingat dari ' || r.dari_label || ': ' || r.pesan,
      public.today_wib(), r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 2. RINGKASAN SELL OUT (dashboard depan)
--    p_store null = semua toko yang bisa dilihat akun ini (TL/Trainer: areanya, PIC: semua).
-- ---------------------------------------------------------------------
create or replace function public.ringkasan_sellout(p_store int, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  with toko as (
    select id from public.stores
     where aktif and public.can_view_store(id) and (p_store is null or id = p_store)
  ), s as (
    select x.tanggal, x.tipe, x.qty, x.subtotal, p.fokus
      from public.sales x left join public.products p on p.id = x.product_id
     where x.store_id in (select id from toko) and x.tanggal between v_bulan and p_tanggal
  ), h as (select * from s where tanggal = p_tanggal)
  select jsonb_build_object(
    'hari', jsonb_build_object(
      'unit', coalesce((select sum(qty) from h where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from h where tipe = 'HP'), 0),
      'fokus_a7pro', coalesce((select sum(qty) from h where fokus = 'A7 Pro'), 0),
      'fokus_reno16', coalesce((select sum(qty) from h where fokus = 'Reno 16'), 0),
      'iot', coalesce((select sum(qty) from h where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from h where tipe = 'IOT'), 0)),
    'bulan', jsonb_build_object(
      'unit', coalesce((select sum(qty) from s where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from s where tipe = 'HP'), 0),
      'fokus_a7pro', coalesce((select sum(qty) from s where fokus = 'A7 Pro'), 0),
      'fokus_reno16', coalesce((select sum(qty) from s where fokus = 'Reno 16'), 0),
      'iot', coalesce((select sum(qty) from s where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from s where tipe = 'IOT'), 0)),
    'target', (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb) from (
                 select jenis, sum(nilai) as total from public.store_targets
                  where store_id in (select id from toko) and bulan = v_bulan group by jenis) t)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 3. KONTRIBUSI PER SERIES & TIPE (tgl 1 s.d. p_tanggal)
--    Satu baris per produk yang terjual: tipe (HP/IOT), grup (A Series, Reno Series, ...), nama, unit, value.
-- ---------------------------------------------------------------------
create or replace function public.kontribusi_tipe(p_store int, p_tanggal date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'grup', grup, 'nama', nama, 'unit', unit, 'value', value, 'unit_hari', unit_hari)
           order by tipe, urutan_grup, unit desc, nama), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.grup, p.grup, '-') as grup, x.nama_produk as nama,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             sum(x.qty) filter (where x.tanggal = p_tanggal) as unit_hari,
             case coalesce(x.grup, p.grup) when 'A Series' then 1 when 'Reno Series' then 2 when 'Find Series' then 3
                                           else 9 end as urutan_grup
        from public.sales x left join public.products p on p.id = x.product_id
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select id from public.stores
                             where aktif and public.can_view_store(id) and (p_store is null or id = p_store))
       group by 1, 2, 3, 7
    ) t
$$;

select 'Tahap 2f siap' as status;
