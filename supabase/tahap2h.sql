-- =====================================================================
-- Daily Report NKA - Tahap 2h
--   1. PC bisa mengedit / menghapus penjualan tanggal 1 s.d. hari ini di bulan berjalan
--      (bulan lalu terkunci untuk PC). Edit penjualan ikut dikirim sebagai notifikasi.
--   2. Insentif hari ini per penjualan (HP & IoT) untuk dashboard PC.
--   3. Export data (Excel) untuk TL / Trainer / PIC dengan rentang tanggal.
-- Jalankan SETELAH tahap2g.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. EDIT PENJUALAN
-- ---------------------------------------------------------------------
create or replace function public.can_write_sales(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select p_tanggal <= public.today_wib() and (
           public.is_pic()
        or (public.my_role() = 'pc' and p_store = public.my_store_id()
              and p_tanggal >= date_trunc('month', public.today_wib()::timestamp)::date)
        or (public.my_role() = 'tl' and public.store_area(p_store) = public.my_area_id()))
$$;

create or replace function public.ev_sale() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.catat_aktivitas(new.store_id, new.diinput_oleh,
      case when new.tipe = 'HP' then 'penjualan_hp' else 'penjualan_iot' end,
      case when new.tipe = 'HP' then 'Penjualan HP' else 'Penjualan IoT' end,
      public.label_aktor(new.diinput_oleh, new.store_id) || ': ' || new.nama_produk || ' x' || new.qty
        || ' · ' || public.rp(new.qty * new.harga)
        || coalesce(' · ' || new.kategori_user, '')
        || coalesce(' · ' || new.metode || coalesce(' ' || new.cara_bayar, ''), '')
        || case when new.tanggal <> public.today_wib() then ' · untuk tgl ' || to_char(new.tanggal, 'DD/MM') else '' end,
      new.tanggal, new.id);
  elsif tg_op = 'UPDATE' then
    if (old.product_id, old.qty, old.tanggal, coalesce(old.metode, ''), coalesce(old.cara_bayar, ''),
        coalesce(old.kategori_user, ''))
       is distinct from
       (new.product_id, new.qty, new.tanggal, coalesce(new.metode, ''), coalesce(new.cara_bayar, ''),
        coalesce(new.kategori_user, '')) then
      perform public.catat_aktivitas(new.store_id, public.my_profile_id(),
        case when new.tipe = 'HP' then 'penjualan_hp' else 'penjualan_iot' end,
        'Penjualan diubah',
        public.label_aktor(public.my_profile_id(), new.store_id) || ' mengubah penjualan tgl ' || to_char(new.tanggal, 'DD/MM')
          || ': ' || old.nama_produk || ' x' || old.qty || ' → ' || new.nama_produk || ' x' || new.qty
          || coalesce(' · ' || new.kategori_user, '')
          || coalesce(' · ' || new.metode || coalesce(' ' || new.cara_bayar, ''), ''),
        new.tanggal, new.id);
    end if;
  elsif coalesce(current_setting('nka.reset', true), '') <> '1' then
    perform public.catat_aktivitas(old.store_id, public.my_profile_id(), 'hapus_penjualan', 'Penjualan dihapus',
      public.label_aktor(public.my_profile_id(), old.store_id) || ' menghapus ' || old.nama_produk || ' x' || old.qty
        || ' (' || to_char(old.tanggal, 'DD/MM') || ')',
      old.tanggal, old.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_ev_sale on public.sales;
create trigger trg_ev_sale after insert or update or delete on public.sales
  for each row execute function public.ev_sale();

-- ---------------------------------------------------------------------
-- 2. INSENTIF HARI INI
--    Insentif per unit sesuai aturan KPI area bulan itu. HP nanti dikali persen tier
--    (persen sementara dari estimasi bulan berjalan); IoT selalu 100%.
-- ---------------------------------------------------------------------
create or replace function public.insentif_harian(p_store int, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_area int;
  v_b date;
  v_persen numeric := 100;
  v_tier text;
  v_est jsonb;
  r jsonb;
begin
  if not public.can_view_store(p_store) then raise exception 'Akses ditolak'; end if;
  select area_id into v_area from public.stores where id = p_store;
  v_b := public.bulan_kpi(v_area, p_tanggal);
  if v_b is null then return jsonb_build_object('ada_aturan', false); end if;
  begin
    v_est := public.estimasi_gaji(p_store, p_tanggal);
    v_persen := coalesce((v_est->>'persen_insentif')::numeric, 100);
    v_tier := v_est->>'tier';
  exception when others then null;
  end;

  with x as (
    select s.id, s.tipe, s.nama_produk, s.qty, s.created_at,
           public.insentif_unit(v_area, v_b, s.product_id, s.tipe, s.grup, s.harga) as per_unit
      from public.sales s
     where s.store_id = p_store and s.tanggal = p_tanggal
  )
  select jsonb_build_object(
    'ada_aturan', true,
    'tier', v_tier,
    'persen_hp', v_persen,
    'total_hp', coalesce((select sum(qty * per_unit) from x where tipe = 'HP'), 0),
    'total_hp_tier', coalesce((select sum(qty * per_unit) from x where tipe = 'HP'), 0) * v_persen / 100,
    'total_iot', coalesce((select sum(qty * per_unit) from x where tipe = 'IOT'), 0),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                'tipe', tipe, 'nama', nama_produk, 'qty', qty, 'per_unit', per_unit, 'insentif', qty * per_unit)
                order by tipe, created_at) from x), '[]'::jsonb)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 3. EXPORT DATA (Excel) - TL / Trainer / PIC, maksimal 93 hari
-- ---------------------------------------------------------------------
create or replace function public.export_data(p_dari date, p_sampai date, p_store int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if public.my_role() not in ('tl', 'trainer', 'pic') then raise exception 'Akses ditolak'; end if;
  if p_sampai < p_dari then raise exception 'Tanggal akhir sebelum tanggal awal'; end if;
  if p_sampai - p_dari > 92 then raise exception 'Rentang maksimal 3 bulan (93 hari)'; end if;

  with toko as (
    select s.id, s.nama, a.nama as area,
           (select nama from public.profiles where store_id = s.id and role = 'pc' and aktif order by created_at limit 1) as pc
      from public.stores s join public.areas a on a.id = s.area_id
     where s.aktif and public.can_view_store(s.id) and (p_store is null or s.id = p_store)
  ), hari as (
    select t.id as store_id, t.nama as toko, t.area, t.pc, d::date as tanggal
      from toko t cross join generate_series(p_dari, p_sampai, interval '1 day') d
  ), jual as (
    select x.store_id, x.tanggal,
           sum(x.qty) filter (where x.tipe = 'HP') as unit_hp,
           sum(x.subtotal) filter (where x.tipe = 'HP') as value_hp,
           sum(x.qty) filter (where p.fokus = 'A7 Pro') as fokus_a7pro,
           sum(x.qty) filter (where p.fokus = 'Reno 16') as fokus_reno16,
           sum(x.qty) filter (where x.tipe = 'IOT') as unit_iot,
           sum(x.subtotal) filter (where x.tipe = 'IOT') as value_iot
      from public.sales x left join public.products p on p.id = x.product_id
     where x.store_id in (select id from toko) and x.tanggal between p_dari and p_sampai
     group by 1, 2
  ), stok as (
    select st.store_id, st.tanggal,
           sum(st.qty) filter (where p.tipe = 'HP') as stok_hp,
           sum(st.qty) filter (where p.tipe <> 'HP') as stok_iot
      from public.stock_daily st join public.products p on p.id = st.product_id
     where st.store_id in (select id from toko) and st.tanggal between p_dari and p_sampai
     group by 1, 2
  ), ms as (
    select c.store_id, c.tanggal, sum(c.unit) as brand_lain
      from public.competitor_sales c
     where c.store_id in (select id from toko) and c.tanggal between p_dari and p_sampai
     group by 1, 2
  ), cek as (
    select l.store_id, l.tanggal, count(*) as cek_limit,
           count(*) filter (where l.leasing = 'Avanto') as avanto,
           count(*) filter (where l.leasing = 'Avanto' and l.hasil = 'Approve') as avanto_approve
      from public.leasing_checks l
     where l.store_id in (select id from toko) and l.tanggal between p_dari and p_sampai
     group by 1, 2
  ), sos as (
    select so.store_id, so.tanggal, sum(so.jumlah) as sosmed
      from public.social_activities so
     where so.store_id in (select id from toko) and so.tanggal between p_dari and p_sampai
     group by 1, 2
  )
  select jsonb_build_object(
    'harian', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', h.tanggal, 'area', h.area, 'toko', h.toko, 'pc', h.pc,
        'unit_hp', coalesce(j.unit_hp, 0), 'value_hp', coalesce(j.value_hp, 0),
        'fokus_a7pro', coalesce(j.fokus_a7pro, 0), 'fokus_reno16', coalesce(j.fokus_reno16, 0),
        'unit_iot', coalesce(j.unit_iot, 0), 'value_iot', coalesce(j.value_iot, 0),
        'stok_hp', st.stok_hp, 'stok_iot', st.stok_iot,
        'ms_brand_lain', m.brand_lain,
        'ms_oppo_pct', case when m.brand_lain is null then null
                            when coalesce(j.unit_hp, 0) + m.brand_lain = 0 then null
                            else round(coalesce(j.unit_hp, 0) * 100.0 / (coalesce(j.unit_hp, 0) + m.brand_lain)) end,
        'cek_limit', coalesce(c.cek_limit, 0), 'cek_avanto', coalesce(c.avanto, 0),
        'avanto_approve', coalesce(c.avanto_approve, 0),
        'sosmed', coalesce(so.sosmed, 0),
        'libur', (select ds.status from public.pc_day_status ds join public.profiles pp on pp.id = ds.pc_id
                   where pp.store_id = h.store_id and ds.tanggal = h.tanggal limit 1),
        'laporan', (select to_char(dr.dikirim_pada at time zone 'Asia/Jakarta', 'HH24:MI') from public.daily_reports dr
                     where dr.store_id = h.store_id and dr.tanggal = h.tanggal))
        order by h.tanggal, h.area, h.toko), '[]'::jsonb)
      from hari h
      left join jual j on j.store_id = h.store_id and j.tanggal = h.tanggal
      left join stok st on st.store_id = h.store_id and st.tanggal = h.tanggal
      left join ms m on m.store_id = h.store_id and m.tanggal = h.tanggal
      left join cek c on c.store_id = h.store_id and c.tanggal = h.tanggal
      left join sos so on so.store_id = h.store_id and so.tanggal = h.tanggal),
    'penjualan', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', x.tanggal, 'toko', t.nama, 'tipe', x.tipe, 'grup', x.grup, 'produk', x.nama_produk,
        'qty', x.qty, 'harga', x.harga, 'subtotal', x.subtotal, 'kategori_user', x.kategori_user,
        'metode', x.metode, 'cara_bayar', x.cara_bayar) order by x.tanggal, t.nama, x.created_at), '[]'::jsonb)
      from public.sales x join toko t on t.id = x.store_id
     where x.tanggal between p_dari and p_sampai),
    'stok', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', st.tanggal, 'toko', t.nama, 'tipe', p.tipe, 'grup', p.grup, 'produk', p.nama, 'qty', st.qty)
        order by st.tanggal, t.nama, p.tipe, p.urutan), '[]'::jsonb)
      from public.stock_daily st join toko t on t.id = st.store_id join public.products p on p.id = st.product_id
     where st.tanggal between p_dari and p_sampai),
    'ms_allbrand', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', d.tanggal, 'toko', t.nama, 'brand', b.nama, 'segmen', d.segmen, 'unit', d.unit)
        order by d.tanggal, t.nama, b.urutan, d.segmen), '[]'::jsonb)
      from public.competitor_sales_detail d join toko t on t.id = d.store_id
      join public.competitor_brands b on b.id = d.brand_id
     where d.tanggal between p_dari and p_sampai),
    'cek_limit', (select coalesce(jsonb_agg(jsonb_build_object(
        'tanggal', l.tanggal, 'toko', t.nama, 'leasing', l.leasing, 'hasil', l.hasil, 'limit', l.limit_disetujui,
        'jam', to_char(l.created_at at time zone 'Asia/Jakarta', 'HH24:MI'))
        order by l.tanggal, t.nama, l.created_at), '[]'::jsonb)
      from public.leasing_checks l join toko t on t.id = l.store_id
     where l.tanggal between p_dari and p_sampai)
  ) into r;
  return r;
end $$;

select 'Tahap 2h siap' as status;
