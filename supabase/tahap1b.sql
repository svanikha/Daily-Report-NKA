-- =====================================================================
-- Daily Report NKA - Tahap 1 revisi (MS Allbrand per segmen, kalender penjualan)
-- Jalankan SETELAH tahap1.sql: SQL Editor -> New query -> tempel -> Run.
-- Aman dijalankan ulang. Tidak ada data yang dihapus.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. MS ALLBRAND: rincian penjualan kompetitor per brand, segmen harga, dan tipe
--    Segmen: lt3 = < 3 jt, 3to6 = 3 jt - 6 jt, gt6 = 6 jt ke atas
--    Total per brand tetap disimpan di competitor_sales (dipakai market share).
-- ---------------------------------------------------------------------
create table if not exists public.competitor_sales_detail (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  brand_id int not null references public.competitor_brands(id),
  segmen text not null check (segmen in ('lt3', '3to6', 'gt6')),
  tipe text not null check (length(trim(tipe)) > 0),
  unit int not null check (unit > 0),
  diinput_oleh uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists competitor_sales_detail_idx on public.competitor_sales_detail(store_id, tanggal);

alter table public.competitor_sales_detail enable row level security;
drop policy if exists competitor_sales_detail_select on public.competitor_sales_detail;
create policy competitor_sales_detail_select on public.competitor_sales_detail for select to authenticated
  using (public.can_view_store(store_id));
-- Ditulis lewat RPC simpan_ms_allbrand; PIC boleh koreksi langsung.
drop policy if exists competitor_sales_detail_pic on public.competitor_sales_detail;
create policy competitor_sales_detail_pic on public.competitor_sales_detail for all to authenticated
  using (public.is_pic()) with check (public.is_pic());

-- Segmen harga dari harga jual (dipakai untuk OPPO)
create or replace function public.segmen_harga(p_harga bigint) returns text
language sql immutable as $$
  select case when p_harga < 3000000 then 'lt3' when p_harga < 6000000 then '3to6' else 'gt6' end
$$;

-- Simpan MS Allbrand satu toko satu tanggal sekaligus (ganti semua rincian lama).
-- p_detail: [{"brand_id":1,"segmen":"3to6","tipe":"Y11d Pro 4/128","unit":2}, ...]
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
begin
  if not public.can_write_daily(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. PC hanya bisa input hari ini sebelum 22.00 WIB.';
  end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  insert into public.competitor_sales_detail (store_id, tanggal, brand_id, segmen, tipe, unit, diinput_oleh)
  select p_store, p_tanggal, (d->>'brand_id')::int, d->>'segmen', trim(d->>'tipe'), (d->>'unit')::int, v_me
    from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) d
   where coalesce((d->>'unit')::int, 0) > 0;
  insert into public.competitor_sales (store_id, tanggal, brand_id, unit, diinput_oleh, updated_at)
  select p_store, p_tanggal, b.id,
         coalesce((select sum(x.unit) from public.competitor_sales_detail x
                    where x.store_id = p_store and x.tanggal = p_tanggal and x.brand_id = b.id), 0),
         v_me, now()
    from public.competitor_brands b
   where b.aktif
  on conflict (store_id, tanggal, brand_id) do update
     set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();
end $$;

-- ---------------------------------------------------------------------
-- 2. LAPORAN: nama modul kompetitor menjadi MS Allbrand
-- ---------------------------------------------------------------------
create or replace function public.laporan_kurang(p_store int, p_tanggal date) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when not exists (select 1 from public.stock_daily where store_id = p_store and tanggal = p_tanggal)
         then 'Stok' end,
    case when not exists (select 1 from public.sales where store_id = p_store and tanggal = p_tanggal)
          and not exists (select 1 from public.checkins where store_id = p_store and tanggal = p_tanggal and modul = 'penjualan')
         then 'Penjualan (atau tandai tidak ada penjualan)' end,
    case when not exists (select 1 from public.competitor_sales where store_id = p_store and tanggal = p_tanggal)
         then 'MS Allbrand' end,
    case when not exists (select 1 from public.display_reports where store_id = p_store and tanggal = p_tanggal)
         then 'Cek display' end
  ], null)
$$;

-- ---------------------------------------------------------------------
-- 3. REKAP TOKO (versi baru)
--    offday_sisa = offday dari tanggal laporan (termasuk) s.d. akhir bulan
--    sisa hari kerja = (hari terakhir - tanggal + 1) - offday_sisa
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
    select x.*, p.fokus, public.segmen_harga(x.harga) as segmen
      from public.sales x left join public.products p on p.id = x.product_id
     where x.store_id = p_store and x.tanggal between v_bulan and p_tanggal
  ), h as (select * from s where tanggal = p_tanggal),
  k as (
    select c.* from public.competitor_sales c where c.store_id = p_store and c.tanggal between v_bulan and p_tanggal
  ),
  kd as (
    select d.*, b.nama as brand, b.urutan
      from public.competitor_sales_detail d join public.competitor_brands b on b.id = d.brand_id
     where d.store_id = p_store and d.tanggal = p_tanggal
  )
  select jsonb_build_object(
    'store_id', p_store,
    'toko', (select nama from public.stores where id = p_store),
    'area', (select nama from public.areas where id = v_area),
    'pc_id', v_pc,
    'pc', (select nama from public.profiles where id = v_pc),
    'tl', (select string_agg(nama, ', ' order by nama) from public.profiles where role = 'tl' and aktif and area_id = v_area),
    'libur', (select status from public.pc_day_status where pc_id = v_pc and tanggal = p_tanggal),
    'offday_sisa', (select count(*) from public.pc_day_status where pc_id = v_pc and tanggal >= p_tanggal and tanggal <= v_akhir),
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
      'iot_value', coalesce((select sum(subtotal) from s where tipe = 'IOT'), 0),
      'kompetitor', coalesce((select sum(unit) from k), 0),
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
    -- MS Allbrand per segmen hari ini: OPPO (dari harga jual) dan rincian kompetitor
    'ms_oppo', jsonb_build_object(
      'lt3', coalesce((select sum(qty) from h where tipe = 'HP' and segmen = 'lt3'), 0),
      '3to6', coalesce((select sum(qty) from h where tipe = 'HP' and segmen = '3to6'), 0),
      'gt6', coalesce((select sum(qty) from h where tipe = 'HP' and segmen = 'gt6'), 0)),
    'ms_detail', (select coalesce(jsonb_agg(jsonb_build_object('brand', brand, 'segmen', segmen, 'tipe', tipe, 'unit', unit)
                                            order by urutan, segmen, unit desc), '[]'::jsonb) from kd),
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
-- 4. KALENDER PENJUALAN (dashboard TL, Trainer, PIC)
--    Per tanggal dalam satu bulan: unit & value HP, unit IoT, unit kompetitor,
--    untuk semua toko di cakupan akun (atau satu toko jika p_store diisi).
-- ---------------------------------------------------------------------
create or replace function public.kalender_penjualan(p_bulan date, p_store int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with toko as (
    select id from public.stores
     where aktif and public.can_view_store(id) and (p_store is null or id = p_store)
  ), hari as (
    select generate_series(date_trunc('month', p_bulan)::date,
                           (date_trunc('month', p_bulan) + interval '1 month - 1 day')::date,
                           interval '1 day')::date as tanggal
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tanggal', h.tanggal,
           'unit', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                               and s.store_id in (select id from toko)), 0),
           'value', coalesce((select sum(subtotal) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                                and s.store_id in (select id from toko)), 0),
           'iot', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'IOT'
                              and s.store_id in (select id from toko)), 0),
           'kompetitor', coalesce((select sum(unit) from public.competitor_sales c where c.tanggal = h.tanggal
                                     and c.store_id in (select id from toko)), 0),
           'lapor', (select count(*) from public.daily_reports d where d.tanggal = h.tanggal
                       and d.store_id in (select id from toko))
         ) order by h.tanggal), '[]'::jsonb)
    from hari h
$$;

select 'Tahap 1 revisi siap' as status;
