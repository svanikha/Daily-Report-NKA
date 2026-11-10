-- =====================================================================
-- Daily Report NKA - Tahap 1 (laporan harian PC)
-- Jalankan SETELAH schema.sql: SQL Editor -> New query -> tempel -> Run.
-- Aman dijalankan ulang (idempotent). Tidak ada data yang dihapus.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CEK DISPLAY: satu baris per toko per hari (foto display menempel ke sini)
-- ---------------------------------------------------------------------
create table if not exists public.display_reports (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  pc_id uuid references public.profiles(id),
  catatan text,
  diinput_oleh uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (store_id, tanggal)
);
alter table public.display_reports enable row level security;
drop policy if exists display_reports_select on public.display_reports;
create policy display_reports_select on public.display_reports for select to authenticated
  using (public.can_view_store(store_id));
drop policy if exists display_reports_write on public.display_reports;
create policy display_reports_write on public.display_reports for all to authenticated
  using (public.can_write_daily(store_id, tanggal)) with check (public.can_write_daily(store_id, tanggal));

alter table public.photos drop constraint if exists photos_ref_tabel_check;
alter table public.photos add constraint photos_ref_tabel_check
  check (ref_tabel in ('breaks', 'display_checks', 'display_reports', 'store_visits'));

-- ---------------------------------------------------------------------
-- 2. JARAK KE TOKO (titik terdekat; Erafone Pangkalanbun punya 2 titik)
-- ---------------------------------------------------------------------
create or replace function public.jarak_m(lat1 double precision, lng1 double precision,
                                          lat2 double precision, lng2 double precision) returns int
language sql immutable as $$
  select round(2 * 6371000 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2)
           + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::int
$$;

create or replace function public.jarak_toko(p_store int, p_lat double precision, p_lng double precision)
returns table (jarak int, radius int, lokasi text)
language sql stable security definer set search_path = public as $$
  select public.jarak_m(p_lat, p_lng, l.latitude, l.longitude), l.radius_m, l.nama_lokasi
    from public.store_locations l
   where l.store_id = p_store
   order by public.jarak_m(p_lat, p_lng, l.latitude, l.longitude)
   limit 1
$$;

-- ---------------------------------------------------------------------
-- 3. ISTIRAHAT (hanya jika PC keluar toko): 1 jam / 2 jam, selfie mulai & kembali
-- Foto diunggah dulu oleh aplikasi ke bucket "bukti" (folder = store_id), lalu RPC ini
-- memvalidasi lokasi di server dan mencatat istirahat + fotonya.
-- ---------------------------------------------------------------------
create or replace function public.mulai_istirahat(p_durasi int, p_path text,
                                                  p_lat double precision, p_lng double precision)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pc uuid := public.my_profile_id();
  v_store int := public.my_store_id();
  v_today date := public.today_wib();
  j record;
  r public.breaks;
  v_photo uuid;
begin
  if v_pc is null or public.my_role() <> 'pc' then raise exception 'Hanya Product Consultant yang bisa memulai istirahat'; end if;
  if p_durasi not in (60, 120) then raise exception 'Durasi istirahat hanya 1 jam atau 2 jam'; end if;
  if exists (select 1 from public.pc_day_status where pc_id = v_pc and tanggal = v_today) then
    raise exception 'Hari ini offday/izin';
  end if;
  if public.time_wib() >= time '22:00' then raise exception 'Sudah lewat pukul 22.00 WIB'; end if;
  if p_path is null or split_part(p_path, '/', 1) <> v_store::text then raise exception 'Selfie wajib diambil'; end if;
  if p_lat is null or p_lng is null then raise exception 'Lokasi wajib aktif untuk selfie istirahat'; end if;
  select * into j from public.jarak_toko(v_store, p_lat, p_lng);
  if j.jarak is not null and j.jarak > j.radius then
    raise exception 'Kamu % m dari toko. Selfie istirahat harus di area toko (maks % m).', j.jarak, j.radius;
  end if;

  insert into public.breaks (store_id, pc_id, tanggal, durasi_menit, jarak_mulai_m)
  values (v_store, v_pc, v_today, p_durasi, j.jarak)
  on conflict (pc_id, tanggal) do nothing
  returning * into r;
  if r.id is null then raise exception 'Istirahat hanya bisa 1 kali dalam sehari'; end if;

  insert into public.photos (store_id, pc_id, ref_tabel, ref_id, path, sumber, waktu_ambil,
                             latitude, longitude, jarak_toko_m, metadata_valid, created_by)
  values (v_store, v_pc, 'breaks', r.id, p_path, 'kamera', now(), p_lat, p_lng, j.jarak, true, v_pc)
  returning id into v_photo;
  update public.breaks set photo_mulai_id = v_photo where id = r.id returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.kembali_ke_toko(p_path text, p_lat double precision, p_lng double precision)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pc uuid := public.my_profile_id();
  v_store int := public.my_store_id();
  j record;
  r public.breaks;
  v_photo uuid;
  v_late int;
begin
  select * into r from public.breaks
   where pc_id = v_pc and tanggal = public.today_wib() and selesai is null;
  if r.id is null then raise exception 'Tidak ada istirahat yang sedang berjalan'; end if;
  if p_path is null or split_part(p_path, '/', 1) <> v_store::text then raise exception 'Selfie wajib diambil'; end if;
  if p_lat is null or p_lng is null then raise exception 'Lokasi wajib aktif untuk selfie kembali'; end if;
  select * into j from public.jarak_toko(v_store, p_lat, p_lng);
  if j.jarak is not null and j.jarak > j.radius then
    raise exception 'Kamu % m dari toko. Selfie kembali harus di area toko (maks % m).', j.jarak, j.radius;
  end if;

  v_late := greatest(0, floor(extract(epoch from (now() - r.mulai)) / 60)::int - r.durasi_menit);
  insert into public.photos (store_id, pc_id, ref_tabel, ref_id, path, sumber, waktu_ambil,
                             latitude, longitude, jarak_toko_m, metadata_valid, created_by)
  values (v_store, v_pc, 'breaks', r.id, p_path, 'kamera', now(), p_lat, p_lng, j.jarak, true, v_pc)
  returning id into v_photo;
  update public.breaks
     set selesai = now(), photo_kembali_id = v_photo, jarak_kembali_m = j.jarak,
         terlambat_menit = v_late, flag = case when v_late > 0 then 'terlambat' end
   where id = r.id
  returning * into r;
  return to_jsonb(r);
end $$;

-- ---------------------------------------------------------------------
-- 4. KIRIM LAPORAN MALAM (batas 22.00 WIB untuk PC)
-- Lengkap = stok pagi + penjualan (atau nihil) + kompetitor + display.
-- ---------------------------------------------------------------------
create or replace function public.laporan_kurang(p_store int, p_tanggal date) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when not exists (select 1 from public.stock_daily where store_id = p_store and tanggal = p_tanggal)
         then 'Stok pagi' end,
    case when not exists (select 1 from public.sales where store_id = p_store and tanggal = p_tanggal)
          and not exists (select 1 from public.checkins where store_id = p_store and tanggal = p_tanggal and modul = 'penjualan')
         then 'Penjualan (atau tandai tidak ada penjualan)' end,
    case when not exists (select 1 from public.competitor_sales where store_id = p_store and tanggal = p_tanggal)
         then 'Penjualan kompetitor' end,
    case when not exists (select 1 from public.display_reports where store_id = p_store and tanggal = p_tanggal)
         then 'Cek display' end
  ], null)
$$;

create or replace function public.kirim_laporan(p_store int, p_tanggal date, p_catatan text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_kurang text[];
  v_pc uuid;
  r public.daily_reports;
begin
  if not public.can_write_daily(p_store, p_tanggal) then
    raise exception 'Laporan tidak bisa dikirim. PC hanya bisa mengirim laporan hari ini sebelum 22.00 WIB.';
  end if;
  v_kurang := public.laporan_kurang(p_store, p_tanggal);
  if array_length(v_kurang, 1) > 0 then
    raise exception 'Laporan belum lengkap: %', array_to_string(v_kurang, ', ');
  end if;
  select id into v_pc from public.profiles where store_id = p_store and role = 'pc' and aktif order by created_at limit 1;
  insert into public.daily_reports (store_id, tanggal, pc_id, dikirim_oleh, catatan)
  values (p_store, p_tanggal, v_pc, public.my_profile_id(), nullif(trim(p_catatan), ''))
  on conflict (store_id, tanggal) do update
     set catatan = coalesce(excluded.catatan, public.daily_reports.catatan)
  returning * into r;
  return to_jsonb(r);
end $$;

-- ---------------------------------------------------------------------
-- 5. REKAP SATU TOKO (isi gambar laporan harian)
-- ---------------------------------------------------------------------
create or replace function public.rekap_toko(p_store int, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  v_akhir date := (date_trunc('month', p_tanggal) + interval '1 month - 1 day')::date;
  v_pc uuid;
  v_area int;
  r jsonb;
begin
  if not public.can_view_store(p_store) then raise exception 'Akses ditolak'; end if;
  select area_id into v_area from public.stores where id = p_store;
  select id into v_pc from public.profiles where store_id = p_store and role = 'pc' and aktif order by created_at limit 1;

  with s as (
    select x.*, p.fokus from public.sales x left join public.products p on p.id = x.product_id
     where x.store_id = p_store and x.tanggal between v_bulan and p_tanggal
  ), h as (select * from s where tanggal = p_tanggal),
  k as (
    select c.* from public.competitor_sales c where c.store_id = p_store and c.tanggal between v_bulan and p_tanggal
  )
  select jsonb_build_object(
    'store_id', p_store,
    'toko', (select nama from public.stores where id = p_store),
    'area', (select nama from public.areas where id = v_area),
    'pc_id', v_pc,
    'pc', (select nama from public.profiles where id = v_pc),
    'tl', (select string_agg(nama, ', ' order by nama) from public.profiles where role = 'tl' and aktif and area_id = v_area),
    'libur', (select status from public.pc_day_status where pc_id = v_pc and tanggal = p_tanggal),
    'offday_sisa', (select count(*) from public.pc_day_status where pc_id = v_pc and tanggal > p_tanggal and tanggal <= v_akhir),
    'hari_akhir', extract(day from v_akhir)::int,
    'hari', jsonb_build_object(
      'unit', coalesce((select sum(qty) from h where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from h where tipe = 'HP'), 0),
      'fokus_a7pro', coalesce((select sum(qty) from h where fokus = 'A7 Pro'), 0),
      'fokus_reno16', coalesce((select sum(qty) from h where fokus = 'Reno 16'), 0),
      'iot', coalesce((select sum(qty) from h where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from h where tipe = 'IOT'), 0),
      'kompetitor', coalesce((select sum(unit) from k where tanggal = p_tanggal), 0)),
    'bulan', jsonb_build_object(
      'unit', coalesce((select sum(qty) from s where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from s where tipe = 'HP'), 0),
      'fokus_a7pro', coalesce((select sum(qty) from s where fokus = 'A7 Pro'), 0),
      'fokus_reno16', coalesce((select sum(qty) from s where fokus = 'Reno 16'), 0),
      'iot', coalesce((select sum(qty) from s where tipe = 'IOT'), 0),
      'kompetitor', coalesce((select sum(unit) from k), 0),
      -- unit OPPO hanya di hari yang data kompetitornya terisi (agar market share adil)
      'unit_hari_kompetitor', coalesce((select sum(qty) from s where tipe = 'HP'
                                         and tanggal in (select distinct tanggal from k)), 0)),
    'target', (select coalesce(jsonb_object_agg(jenis, nilai), '{}'::jsonb)
                 from public.store_targets where store_id = p_store and bulan = v_bulan),
    'penjualan', (select coalesce(jsonb_agg(jsonb_build_object(
                      'nama', nama_produk, 'tipe', tipe, 'qty', qty, 'subtotal', subtotal,
                      'metode', metode, 'cara_bayar', cara_bayar) order by created_at), '[]'::jsonb) from h),
    'nihil_penjualan', exists (select 1 from public.checkins where store_id = p_store and tanggal = p_tanggal and modul = 'penjualan'),
    'kompetitor', (select coalesce(jsonb_agg(jsonb_build_object('brand', b.nama, 'unit', c.unit)
                                             order by c.unit desc, b.urutan), '[]'::jsonb)
                     from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
                    where c.store_id = p_store and c.tanggal = p_tanggal and c.unit > 0),
    'kompetitor_terisi', exists (select 1 from public.competitor_sales where store_id = p_store and tanggal = p_tanggal),
    'cash_unit', coalesce((select sum(qty) from h where tipe = 'HP' and metode = 'Cash'), 0),
    'kredit_unit', coalesce((select sum(qty) from h where tipe = 'HP' and metode = 'Kredit'), 0),
    'kredit_top', (select cara_bayar from h where metode = 'Kredit' group by cara_bayar order by sum(qty) desc limit 1),
    'stok_waktu', (select min(waktu_input) from public.stock_daily where store_id = p_store and tanggal = p_tanggal),
    'stok_kosong_fokus', (select coalesce(jsonb_agg(p.nama order by p.urutan), '[]'::jsonb)
                            from public.products p
                            left join public.stock_daily sd on sd.product_id = p.id and sd.store_id = p_store and sd.tanggal = p_tanggal
                           where p.fokus is not null and p.aktif and coalesce(sd.qty, 0) = 0),
    'display', (select coalesce(jsonb_agg(jsonb_build_object('nama', i.nama, 'ok', coalesce(d.ok, false)) order by i.urutan), '[]'::jsonb)
                  from public.checklist_items i
                  left join public.display_checks d on d.item_id = i.id and d.store_id = p_store and d.tanggal = p_tanggal
                 where i.aktif),
    'display_terisi', exists (select 1 from public.display_reports where store_id = p_store and tanggal = p_tanggal),
    'display_foto', (select count(*) from public.photos ph join public.display_reports dr on dr.id = ph.ref_id
                      where dr.store_id = p_store and dr.tanggal = p_tanggal),
    'istirahat', (select to_jsonb(b) from public.breaks b where b.store_id = p_store and b.tanggal = p_tanggal limit 1),
    'laporan', (select to_jsonb(x) from public.daily_reports x where x.store_id = p_store and x.tanggal = p_tanggal),
    'kurang', to_jsonb(public.laporan_kurang(p_store, p_tanggal))
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 6. STATUS HARI INI SEMUA TOKO (dashboard TL, Trainer, PIC)
-- ---------------------------------------------------------------------
create or replace function public.status_toko(p_tanggal date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.area_id, x.id), '[]'::jsonb)
    from (
      select s.id, s.area_id, jsonb_build_object(
        'store_id', s.id, 'toko', s.nama, 'area_id', s.area_id, 'area', a.nama, 'punya_pc', s.punya_pc,
        'pc_id', pc.id, 'pc', pc.nama,
        'libur', (select d.status from public.pc_day_status d where d.pc_id = pc.id and d.tanggal = p_tanggal),
        'stok_waktu', (select min(waktu_input) from public.stock_daily where store_id = s.id and tanggal = p_tanggal),
        'unit', coalesce((select sum(qty) from public.sales where store_id = s.id and tanggal = p_tanggal and tipe = 'HP'), 0),
        'value', coalesce((select sum(subtotal) from public.sales where store_id = s.id and tanggal = p_tanggal and tipe = 'HP'), 0),
        'iot', coalesce((select sum(qty) from public.sales where store_id = s.id and tanggal = p_tanggal and tipe = 'IOT'), 0),
        'unit_bulan', coalesce((select sum(qty) from public.sales where store_id = s.id and tipe = 'HP'
                                  and tanggal between date_trunc('month', p_tanggal)::date and p_tanggal), 0),
        'value_bulan', coalesce((select sum(subtotal) from public.sales where store_id = s.id and tipe = 'HP'
                                  and tanggal between date_trunc('month', p_tanggal)::date and p_tanggal), 0),
        'target_unit', (select nilai from public.store_targets where store_id = s.id and jenis = 'unit'
                           and bulan = date_trunc('month', p_tanggal)::date),
        'target_value', (select nilai from public.store_targets where store_id = s.id and jenis = 'value'
                           and bulan = date_trunc('month', p_tanggal)::date),
        'nihil', exists (select 1 from public.checkins where store_id = s.id and tanggal = p_tanggal and modul = 'penjualan'),
        'kompetitor_terisi', exists (select 1 from public.competitor_sales where store_id = s.id and tanggal = p_tanggal),
        'kompetitor_unit', coalesce((select sum(unit) from public.competitor_sales where store_id = s.id and tanggal = p_tanggal), 0),
        'display_terisi', exists (select 1 from public.display_reports where store_id = s.id and tanggal = p_tanggal),
        'laporan_pada', (select dikirim_pada from public.daily_reports where store_id = s.id and tanggal = p_tanggal),
        'istirahat', (select jsonb_build_object('mulai', b.mulai, 'selesai', b.selesai, 'durasi_menit', b.durasi_menit,
                                                'terlambat_menit', b.terlambat_menit, 'flag', b.flag)
                        from public.breaks b where b.store_id = s.id and b.tanggal = p_tanggal limit 1)
      ) as j
        from public.stores s
        join public.areas a on a.id = s.area_id
        left join lateral (select p.id, p.nama from public.profiles p
                            where p.store_id = s.id and p.role = 'pc' and p.aktif order by p.created_at limit 1) pc on true
       where s.aktif and public.can_view_store(s.id)
    ) x
$$;

select 'Tahap 1 siap' as status;
