-- =====================================================================
-- Daily Report NKA - KPI, insentif, dan estimasi gaji PC
-- Semua aturan disimpan PER AREA PER BULAN dan bisa diedit PIC (semua area),
-- TL & Trainer (areanya). Bulan tanpa aturan memakai aturan bulan terakhir sebelumnya.
--
-- Rumus estimasi gaji (bulan berjalan, dari pencapaian toko PC):
--   Tier ditentukan dari value HP (dan unit HP untuk value < 70 jt)
--   Gaji pokok   = UMR area - potongan sesuai unit HP   (tier dengan "gaji % UMR": UMR x persen)
--   Insentif HP  = jumlah insentif per unit HP x persen insentif tier
--   Insentif IoT = jumlah insentif per unit IoT (100%)
--   Bonus        = aturan bonus yang tercapai (satu grup: ambil yang terbesar)
--   Denda        = aturan denda yang tidak tercapai
--   Estimasi     = gaji pokok + insentif HP + insentif IoT + bonus - denda
--
-- Data awal: November 2026, angka sama untuk 3 area (silakan diubah per area).
-- Jalankan SETELAH tahap1k.sql. Aman dijalankan ulang (data awal hanya diisi jika belum ada).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABEL ATURAN
-- ---------------------------------------------------------------------
create table if not exists public.gaji_area (
  area_id int not null references public.areas(id),
  bulan date not null check (extract(day from bulan) = 1),
  umr bigint not null check (umr >= 0),
  primary key (area_id, bulan)
);

-- Tier: dicocokkan berurutan (urutan kecil dulu), yang pertama cocok dipakai.
create table if not exists public.kpi_tier (
  id bigserial primary key,
  area_id int not null references public.areas(id),
  bulan date not null,
  urutan int not null default 0,
  nama text not null,
  value_min bigint,            -- value HP >= value_min (kosong = tanpa batas bawah)
  value_max bigint,            -- value HP <  value_max (kosong = tanpa batas atas)
  unit_min int,                -- unit HP >= unit_min (kosong = tidak dicek)
  persen_insentif numeric not null default 100 check (persen_insentif between 0 and 100),
  gaji_persen_umr numeric check (gaji_persen_umr between 0 and 100)   -- diisi: gaji pokok = UMR x persen
);
create index if not exists kpi_tier_idx on public.kpi_tier(area_id, bulan, urutan);

-- Potongan gaji pokok menurut unit HP: unit_min <= unit <= unit_max
create table if not exists public.kpi_potongan (
  id bigserial primary key,
  area_id int not null references public.areas(id),
  bulan date not null,
  unit_min int not null default 0,
  unit_max int,                -- kosong = tanpa batas atas
  potongan bigint not null default 0 check (potongan >= 0)
);
create index if not exists kpi_potongan_idx on public.kpi_potongan(area_id, bulan);

-- Bonus & denda.
-- metrik: unit_hp, value_hp, unit_fokus (A7 Pro + Reno 16), unit_a7_reno (A7 Pro + semua Reno Series),
--         unit_iot, unit_produk (nama produk mengandung filter), cek_limit (jumlah cek limit, filter = nama leasing)
-- Bonus: berlaku jika batas_min <= nilai metrik <= batas_max. Jumlah = nilai (atau nilai x metrik jika per_unit).
--        Beberapa bonus dengan grup sama: hanya yang terbesar.
-- Denda: berlaku jika nilai metrik < batas_min. Jumlah = nilai (atau nilai x kekurangan jika per_unit).
create table if not exists public.kpi_aturan (
  id bigserial primary key,
  area_id int not null references public.areas(id),
  bulan date not null,
  jenis text not null check (jenis in ('bonus', 'denda')),
  nama text not null,
  metrik text not null check (metrik in ('unit_hp', 'value_hp', 'unit_fokus', 'unit_a7_reno', 'unit_iot', 'unit_produk', 'cek_limit')),
  filter text,
  batas_min numeric not null default 0,
  batas_max numeric,
  nilai bigint not null check (nilai >= 0),
  per_unit boolean not null default false,
  grup text,
  urutan int not null default 0
);
create index if not exists kpi_aturan_idx on public.kpi_aturan(area_id, bulan, jenis, urutan);

-- Insentif per unit produk
create table if not exists public.insentif_produk (
  area_id int not null references public.areas(id),
  bulan date not null,
  product_id int not null references public.products(id) on delete cascade,
  nilai bigint not null default 0 check (nilai >= 0),
  primary key (area_id, bulan, product_id)
);

-- Insentif produk yang tidak ada di daftar (OTHERS)
create table if not exists public.insentif_lain (
  area_id int not null references public.areas(id),
  bulan date not null,
  kode text not null check (kode in ('hp_lt2', 'hp_2to3', 'hp_gt3', 'hp_reno', 'hp_find', 'iot_lain')),
  nilai bigint not null default 0 check (nilai >= 0),
  primary key (area_id, bulan, kode)
);

-- ---------------------------------------------------------------------
-- 2. HAK AKSES: semua akun boleh melihat (PC bisa melihat aturan areanya);
--    ubah: PIC semua area, TL & Trainer areanya sendiri
-- ---------------------------------------------------------------------
create or replace function public.can_manage_area(p_area int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_pic() or (public.my_role() in ('tl', 'trainer') and p_area = public.my_area_id())
$$;

do $$
declare t text;
begin
  foreach t in array array['gaji_area', 'kpi_tier', 'kpi_potongan', 'kpi_aturan', 'insentif_produk', 'insentif_lain'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_manage', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.can_manage_area(area_id)) with check (public.can_manage_area(area_id))', t || '_manage', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. FUNGSI
-- ---------------------------------------------------------------------
-- Bulan aturan yang berlaku: bulan itu, atau bulan terakhir sebelumnya yang punya aturan
create or replace function public.bulan_kpi(p_area int, p_bulan date) returns date
language sql stable security definer set search_path = public as $$
  select max(bulan) from public.gaji_area where area_id = p_area and bulan <= date_trunc('month', p_bulan)::date
$$;

create or replace function public.insentif_unit(p_area int, p_bulan date, p_product int, p_tipe text,
                                                p_grup text, p_harga bigint) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nilai from public.insentif_produk where area_id = p_area and bulan = p_bulan and product_id = p_product),
    (select nilai from public.insentif_lain where area_id = p_area and bulan = p_bulan and kode =
       case when p_tipe <> 'HP' then 'iot_lain'
            when p_grup = 'Reno Series' then 'hp_reno'
            when p_grup = 'Find Series' then 'hp_find'
            when p_harga < 2000000 then 'hp_lt2'
            when p_harga <= 3000000 then 'hp_2to3'
            else 'hp_gt3' end),
    0)
$$;

-- Salin semua aturan satu area dari bulan p_dari ke bulan p_ke (aturan lama di p_ke diganti)
create or replace function public.salin_kpi(p_area int, p_dari date, p_ke date) returns void
language plpgsql security definer set search_path = public as $$
declare
  d date := date_trunc('month', p_dari)::date;
  k date := date_trunc('month', p_ke)::date;
begin
  if not public.can_manage_area(p_area) then raise exception 'Area ini di luar wewenang kamu'; end if;
  if d = k then return; end if;
  if not exists (select 1 from public.gaji_area where area_id = p_area and bulan = d) then
    raise exception 'Bulan sumber belum punya aturan';
  end if;
  delete from public.gaji_area where area_id = p_area and bulan = k;
  delete from public.kpi_tier where area_id = p_area and bulan = k;
  delete from public.kpi_potongan where area_id = p_area and bulan = k;
  delete from public.kpi_aturan where area_id = p_area and bulan = k;
  delete from public.insentif_produk where area_id = p_area and bulan = k;
  delete from public.insentif_lain where area_id = p_area and bulan = k;
  insert into public.gaji_area select area_id, k, umr from public.gaji_area where area_id = p_area and bulan = d;
  insert into public.kpi_tier (area_id, bulan, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr)
    select area_id, k, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr
      from public.kpi_tier where area_id = p_area and bulan = d;
  insert into public.kpi_potongan (area_id, bulan, unit_min, unit_max, potongan)
    select area_id, k, unit_min, unit_max, potongan from public.kpi_potongan where area_id = p_area and bulan = d;
  insert into public.kpi_aturan (area_id, bulan, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan)
    select area_id, k, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan
      from public.kpi_aturan where area_id = p_area and bulan = d;
  insert into public.insentif_produk select area_id, k, product_id, nilai from public.insentif_produk where area_id = p_area and bulan = d;
  insert into public.insentif_lain select area_id, k, kode, nilai from public.insentif_lain where area_id = p_area and bulan = d;
end $$;

-- Estimasi gaji satu toko (PC-nya) pada bulan tanggal p_tanggal, dihitung s.d. p_tanggal
create or replace function public.estimasi_gaji(p_store int, p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_area int;
  v_awal date := date_trunc('month', p_tanggal)::date;
  v_b date;
  v_umr bigint;
  v_unit numeric; v_value numeric; v_fokus numeric; v_a7reno numeric; v_iot numeric;
  v_ins_hp numeric; v_ins_iot numeric;
  t record;
  v_tier_nama text;
  v_persen numeric := 0;
  v_gpu numeric;
  v_pot bigint;
  v_gaji numeric;
  a record;
  v_m numeric;
  v_amt numeric;
  v_bonus jsonb := '[]'::jsonb;
  v_denda jsonb := '[]'::jsonb;
  v_grup jsonb := '{}'::jsonb;
  v_tot_bonus numeric := 0;
  v_tot_denda numeric := 0;
  v_tiers jsonb;
begin
  if not public.can_view_store(p_store) then raise exception 'Akses ditolak'; end if;
  select area_id into v_area from public.stores where id = p_store;
  v_b := public.bulan_kpi(v_area, p_tanggal);
  if v_b is null then return jsonb_build_object('ada_aturan', false); end if;
  select umr into v_umr from public.gaji_area where area_id = v_area and bulan = v_b;

  -- Pencapaian bulan berjalan
  select coalesce(sum(s.qty) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.subtotal) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.qty) filter (where p.fokus is not null), 0),
         coalesce(sum(s.qty) filter (where p.fokus = 'A7 Pro' or s.grup = 'Reno Series'), 0),
         coalesce(sum(s.qty) filter (where s.tipe = 'IOT'), 0),
         coalesce(sum(s.qty * public.insentif_unit(v_area, v_b, s.product_id, s.tipe, s.grup, s.harga)) filter (where s.tipe = 'HP'), 0),
         coalesce(sum(s.qty * public.insentif_unit(v_area, v_b, s.product_id, s.tipe, s.grup, s.harga)) filter (where s.tipe = 'IOT'), 0)
    into v_unit, v_value, v_fokus, v_a7reno, v_iot, v_ins_hp, v_ins_iot
    from public.sales s left join public.products p on p.id = s.product_id
   where s.store_id = p_store and s.tanggal between v_awal and p_tanggal;

  -- Tier
  for t in select * from public.kpi_tier where area_id = v_area and bulan = v_b order by urutan, id loop
    if (t.value_min is null or v_value >= t.value_min)
       and (t.value_max is null or v_value < t.value_max)
       and (t.unit_min is null or v_unit >= t.unit_min) then
      v_tier_nama := t.nama;
      v_persen := t.persen_insentif;
      v_gpu := t.gaji_persen_umr;
      exit;
    end if;
  end loop;

  -- Gaji pokok
  select potongan into v_pot from public.kpi_potongan
   where area_id = v_area and bulan = v_b and v_unit >= unit_min and (unit_max is null or v_unit <= unit_max)
   order by unit_min desc limit 1;
  if v_gpu is not null then
    v_gaji := v_umr * v_gpu / 100;
    v_pot := null;
  else
    v_gaji := v_umr - coalesce(v_pot, 0);
  end if;

  -- Bonus & denda
  for a in select * from public.kpi_aturan where area_id = v_area and bulan = v_b order by jenis, urutan, id loop
    v_m := case a.metrik
      when 'unit_hp' then v_unit
      when 'value_hp' then v_value
      when 'unit_fokus' then v_fokus
      when 'unit_a7_reno' then v_a7reno
      when 'unit_iot' then v_iot
      when 'unit_produk' then coalesce((select sum(x.qty) from public.sales x
                                          where x.store_id = p_store and x.tanggal between v_awal and p_tanggal
                                            and x.nama_produk ilike '%' || coalesce(a.filter, '') || '%'), 0)
      when 'cek_limit' then coalesce((select count(*) from public.leasing_checks x
                                        where x.store_id = p_store and x.tanggal between v_awal and p_tanggal
                                          and (a.filter is null or x.leasing = a.filter)), 0)
      else 0 end;
    if a.jenis = 'bonus' then
      if v_m >= a.batas_min and (a.batas_max is null or v_m <= a.batas_max) then
        v_amt := case when a.per_unit then a.nilai * v_m else a.nilai end;
        if a.grup is not null and coalesce((v_grup ->> a.grup)::numeric, -1) >= v_amt then
          continue;
        end if;
        if a.grup is not null then
          -- ganti bonus grup yang sama yang lebih kecil
          v_bonus := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_bonus) e where e ->> 'grup' is distinct from a.grup), '[]'::jsonb);
          v_grup := v_grup || jsonb_build_object(a.grup, v_amt);
        end if;
        v_bonus := v_bonus || jsonb_build_array(jsonb_build_object('nama', a.nama, 'grup', a.grup, 'capai', v_m, 'jumlah', v_amt));
      end if;
    else
      if v_m < a.batas_min then
        v_amt := case when a.per_unit then a.nilai * (a.batas_min - v_m) else a.nilai end;
        v_denda := v_denda || jsonb_build_array(jsonb_build_object('nama', a.nama, 'capai', v_m, 'target', a.batas_min, 'jumlah', v_amt));
      end if;
    end if;
  end loop;
  select coalesce(sum((e ->> 'jumlah')::numeric), 0) into v_tot_bonus from jsonb_array_elements(v_bonus) e;
  select coalesce(sum((e ->> 'jumlah')::numeric), 0) into v_tot_denda from jsonb_array_elements(v_denda) e;

  select coalesce(jsonb_agg(jsonb_build_object('nama', nama, 'value_min', value_min, 'value_max', value_max,
                                               'unit_min', unit_min, 'persen', persen_insentif, 'gaji_persen_umr', gaji_persen_umr)
                            order by urutan, id), '[]'::jsonb)
    into v_tiers from public.kpi_tier where area_id = v_area and bulan = v_b;

  return jsonb_build_object(
    'ada_aturan', true,
    'bulan_aturan', v_b,
    'area', (select nama from public.areas where id = v_area),
    'umr', v_umr,
    'unit_hp', v_unit, 'value_hp', v_value, 'unit_fokus', v_fokus, 'unit_a7_reno', v_a7reno, 'unit_iot', v_iot,
    'tier', v_tier_nama,
    'persen_insentif', v_persen,
    'gaji_persen_umr', v_gpu,
    'potongan', v_pot,
    'gaji_pokok', round(v_gaji),
    'insentif_hp_penuh', v_ins_hp,
    'insentif_hp', round(v_ins_hp * v_persen / 100),
    'insentif_iot', v_ins_iot,
    'bonus', v_bonus,
    'denda', v_denda,
    'total_bonus', v_tot_bonus,
    'total_denda', v_tot_denda,
    'total', round(v_gaji + v_ins_hp * v_persen / 100 + v_ins_iot + v_tot_bonus - v_tot_denda),
    'tiers', v_tiers
  );
end $$;

-- ---------------------------------------------------------------------
-- 4. DATA AWAL NOVEMBER 2026 (sama untuk 3 area, hanya jika area itu belum punya aturan)
-- ---------------------------------------------------------------------
do $$
declare
  a record;
  b date := date '2026-11-01';
begin
  for a in select id, nama from public.areas loop
    if exists (select 1 from public.gaji_area where area_id = a.id) then continue; end if;

    insert into public.gaji_area values (a.id, b, case when a.nama = 'Palangkaraya' then 3724700 else 3756700 end);

    insert into public.kpi_tier (area_id, bulan, urutan, nama, value_min, value_max, unit_min, persen_insentif, gaji_persen_umr) values
      (a.id, b, 1, 'Tier 1', 160000000, null, null, 100, null),
      (a.id, b, 2, 'Tier 2', 130000000, 160000000, null, 90, null),
      (a.id, b, 3, 'Tier 3', 90000000, 130000000, null, 70, null),
      (a.id, b, 4, 'Tier 4', 70000000, 90000000, null, 60, null),
      (a.id, b, 5, 'Tier 5', null, 70000000, 15, 100, null),
      (a.id, b, 6, 'Tier 6', null, 70000000, 10, 50, null),
      (a.id, b, 7, 'Tier 7', null, 70000000, null, 0, 50);

    insert into public.kpi_potongan (area_id, bulan, unit_min, unit_max, potongan) values
      (a.id, b, 70, null, 0),
      (a.id, b, 60, 69, 1200000),
      (a.id, b, 50, 59, 1300000),
      (a.id, b, 40, 49, 1400000),
      (a.id, b, 0, 39, 1500000);

    insert into public.kpi_aturan (area_id, bulan, jenis, nama, metrik, filter, batas_min, batas_max, nilai, per_unit, grup, urutan) values
      (a.id, b, 'bonus', 'Bonus HP 30 unit', 'unit_hp', null, 30, null, 300000, false, 'bonus_hp', 1),
      (a.id, b, 'bonus', 'Bonus HP 40 unit', 'unit_hp', null, 40, null, 400000, false, 'bonus_hp', 2),
      (a.id, b, 'bonus', 'Bonus HP 50 unit', 'unit_hp', null, 50, null, 500000, false, 'bonus_hp', 3),
      (a.id, b, 'bonus', 'Bonus HP 60 unit', 'unit_hp', null, 60, null, 600000, false, 'bonus_hp', 4),
      (a.id, b, 'bonus', 'Bonus HP 70 unit ke atas', 'unit_hp', null, 70, null, 800000, false, 'bonus_hp', 5),
      (a.id, b, 'bonus', 'Reno 16 + A7 Pro 5-10 unit (30K/unit)', 'unit_fokus', null, 5, 10, 30000, true, 'bonus_fokus', 6),
      (a.id, b, 'bonus', 'Reno 16 + A7 Pro 11 unit ke atas (50K/unit)', 'unit_fokus', null, 11, null, 50000, true, 'bonus_fokus', 7),
      (a.id, b, 'bonus', 'IoT 10 unit ke atas', 'unit_iot', null, 10, null, 200000, false, 'bonus_iot', 8),
      (a.id, b, 'bonus', 'Enco Air 5 Series minimal 3 unit', 'unit_produk', 'Air5', 3, null, 200000, false, 'bonus_enco', 9),
      (a.id, b, 'denda', 'A7 Pro + Reno Series 0 unit', 'unit_a7_reno', null, 1, null, 200000, false, null, 1),
      (a.id, b, 'denda', 'IoT 0 unit', 'unit_iot', null, 1, null, 100000, false, null, 2),
      (a.id, b, 'denda', 'Cek limit Avanto kurang dari 20 kali (10K/kekurangan)', 'cek_limit', 'Avanto', 20, null, 10000, true, null, 3);

    insert into public.insentif_lain (area_id, bulan, kode, nilai) values
      (a.id, b, 'hp_lt2', 15000), (a.id, b, 'hp_2to3', 30000), (a.id, b, 'hp_gt3', 50000),
      (a.id, b, 'hp_reno', 100000), (a.id, b, 'hp_find', 120000), (a.id, b, 'iot_lain', 0);

    insert into public.insentif_produk (area_id, bulan, product_id, nilai)
    select a.id, b, p.id, v.nilai
      from (values
        ('A7 PRO 5G [6/256]', 140000), ('A7 PRO MAX 5G [8/256]', 180000), ('FIND X10 [12/512]', 400000),
        ('A6X [4/64]', 20000), ('A6X [4/128]', 30000), ('A6C [4/64]', 30000), ('A6C [4/128]', 40000),
        ('A6X [6/128]', 45000), ('A6X [8/128]', 50000), ('A6X [6/256]', 55000), ('A6 [6/128]', 90000),
        ('A6 [6/256]', 110000), ('A6S [8/128]', 90000), ('A6S [8/256]', 110000),
        ('RENO 16 F 5G [8/128]', 150000), ('RENO 16 F 5G [8/256]', 170000), ('RENO 16 5G [8/256]', 200000),
        ('RENO 16 5G [12/256]', 220000), ('RENO 16 PRO 5G [12/256]', 250000),
        ('RENO 15 F 5G [8/128]', 100000), ('RENO 15 F 5G [8/256]', 120000), ('RENO 15 F 5G [12/256]', 130000),
        ('RENO 15 5G [8/256]', 160000), ('RENO 15 5G [12/256]', 180000), ('RENO 15 PRO MAX [12/512]', 220000),
        ('A6 PRO 4G [8/128]', 70000), ('A6 PRO 4G [8/256]', 80000), ('A6 PRO 5G [8/256]', 90000),
        ('FIND X9 [12/256]', 220000), ('FIND X9 [16/512]', 270000), ('FIND X9 PRO [16/512]', 300000),
        ('FIND X9S [12/256]', 280000), ('FIND X9S [12/512]', 300000), ('FIND X9 ULTRA [12/512]', 420000),
        ('FIND X9 ULTRA [16/1TB]', 550000), ('FIND N5 FOLD', 500000),
        ('OPPO Pad 3 Matte Display', 150000), ('OPPO PAD 5 Matte Display Edition 256GB 8GB Star', 130000),
        ('PAD2 8+256GB', 120000), ('OPPO Watch X3 OWWE261 Misty Titanium', 120000),
        ('OPPO Watch X3 OWWE261 Obsidian Black', 120000), ('WATCH X2 OWWE251', 100000), ('WATCH X OWWE231', 100000),
        ('OPPO Pad Neo', 100000), ('OPPO Watch X2 Mini OWWE242', 100000), ('PAD AIR 4+128 Purple', 100000),
        ('OPPO Pad SE Matte Display Edition', 100000), ('OPPO Watch S Silver Gleam', 80000), ('PAD AIR 4+64 GREY', 80000),
        ('OPPO Watch S Phantom Black', 80000), ('OPPO Watch S Air Silver', 80000),
        ('OPPO Enco Clip2 Open Earbuds1 ETEN1', 50000), ('Enco X3i', 60000), ('Enco X3s True Wireless Noise Cancelling', 60000),
        ('OPPO Bubble VBG06', 20000), ('OPPO Enco Air5s ETEF1', 50000), ('Enco Air2 Pro', 50000), ('OPPO BAND 2', 50000),
        ('OPPO Enco Air5 ETEP1', 40000), ('OPPO Enco Air4', 30000), ('Enco Air3', 30000), ('OPPO BAND (BLACK PURPLE)', 25000),
        ('OPPO Enco Air3i True Wireless', 35000), ('ENCO BUDS2', 20000), ('OPPO Enco Buds3 Pro', 20000),
        ('OPPO Enco Buds3 True Wireless Earbuds E', 15000)
      ) as v(nama, nilai)
      join public.products p on p.nama = v.nama
    on conflict do nothing;
  end loop;
end $$;

select a.nama as area, g.umr,
       (select count(*) from public.kpi_tier t where t.area_id = a.id) as tier,
       (select count(*) from public.kpi_aturan k where k.area_id = a.id) as bonus_denda,
       (select count(*) from public.insentif_produk i where i.area_id = a.id) as insentif_produk
  from public.areas a left join public.gaji_area g on g.area_id = a.id
 order by a.id;
