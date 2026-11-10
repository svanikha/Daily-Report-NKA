-- =====================================================================
-- Daily Report NKA - Skema database Supabase (project terpisah dari Daily Report OS)
-- Jalankan SELURUH file ini sekali di Supabase: SQL Editor -> New query
-- -> tempel -> Run. Aman dijalankan ulang (idempotent).
--
-- Peran: pc (Product Consultant), tl (Tim Leader), trainer, pic (PIC NKA)
-- Semua tanggal & batas waktu memakai WIB (Asia/Jakarta).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TABEL MASTER
-- ---------------------------------------------------------------------
create table if not exists public.retail_accounts (
  id serial primary key,
  nama text not null unique
);

create table if not exists public.areas (
  id serial primary key,
  nama text not null unique
);

create table if not exists public.stores (
  id serial primary key,
  nama text not null unique,
  retail_account_id int not null references public.retail_accounts(id),
  area_id int not null references public.areas(id),
  punya_pc boolean not null default true,      -- Erafone Rajawali: false (diinput TL)
  aktif boolean not null default true
);

-- Titik GPS toko. Satu toko boleh punya lebih dari satu titik (Erafone Pangkalanbun: 2 titik).
create table if not exists public.store_locations (
  id serial primary key,
  store_id int not null references public.stores(id) on delete cascade,
  nama_lokasi text not null,
  latitude double precision not null,
  longitude double precision not null,
  radius_m int not null default 100 check (radius_m between 20 and 2000),
  unique (store_id, nama_lokasi)
);

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  role text not null check (role in ('pc', 'tl', 'trainer', 'pic')),
  store_id int references public.stores(id),   -- wajib untuk PC
  area_id int references public.areas(id),     -- wajib untuk TL & Trainer; PIC = semua area
  email text not null unique,
  auth_uid uuid unique references auth.users(id) on delete set null,
  aktif boolean not null default true,
  fcm_token text,
  created_at timestamptz not null default now(),
  check ((role = 'pc' and store_id is not null)
      or (role in ('tl', 'trainer') and area_id is not null)
      or role = 'pic')
);

create table if not exists public.products (
  id serial primary key,
  tipe text not null check (tipe in ('HP', 'IOT')),
  nama text not null,
  grup text not null,
  harga bigint not null check (harga >= 0),
  fokus text check (fokus in ('A7 Pro', 'Reno 16')),
  urutan int not null default 0,
  aktif boolean not null default true,
  diubah_oleh uuid references public.profiles(id),
  diubah_pada timestamptz not null default now(),
  unique (tipe, nama)
);

create table if not exists public.competitor_brands (
  id serial primary key,
  nama text not null unique,
  urutan int not null default 0,
  aktif boolean not null default true
);

create table if not exists public.checklist_items (
  id serial primary key,
  nama text not null unique,
  keterangan text,
  urutan int not null default 0,
  aktif boolean not null default true
);

-- ---------------------------------------------------------------------
-- 2. TABEL TRANSAKSI HARIAN
-- ---------------------------------------------------------------------
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid not null references public.profiles(id),
  nama text not null,
  no_hp text not null,
  kategori text not null check (kategori in ('A Series', 'Reno Series', 'Find Series', 'IoT')),
  status text not null default 'Asking' check (status in ('Asking', 'Probing', 'Closing')),
  produk_minat text,
  catatan text,
  last_contacted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists contacts_pc_idx on public.contacts(pc_id);

create table if not exists public.contact_logs (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.contacts(id) on delete cascade,
  pc_id uuid not null references public.profiles(id),
  channel text not null check (channel in ('telepon', 'whatsapp', 'wa_bisnis', 'status')),
  dihubungi boolean not null default false,
  hasil text,
  status_baru text check (status_baru in ('Asking', 'Probing', 'Closing')),
  waktu timestamptz not null default now()
);
create index if not exists contact_logs_pc_idx on public.contact_logs(pc_id, waktu);

-- Penjualan OPPO, dicatat per toko. pc_id kosong untuk toko non PC (Rajawali).
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid references public.profiles(id),
  diinput_oleh uuid not null references public.profiles(id),   -- diisi otomatis oleh trigger
  tanggal date not null,
  product_id int references public.products(id),
  tipe text not null check (tipe in ('HP', 'IOT')),
  nama_produk text not null,
  grup text,
  qty int not null check (qty > 0),
  harga bigint not null check (harga >= 0),
  subtotal bigint generated always as (qty * harga) stored,
  metode text check (metode in ('Cash', 'Kredit')),
  cara_bayar text,
  contact_id uuid references public.contacts(id) on delete set null,
  created_at timestamptz not null default now(),
  check (
    (tipe = 'IOT' and metode is null and cara_bayar is null)
    or (metode = 'Cash' and cara_bayar in ('Transfer', 'Tunai'))
    or (metode = 'Kredit' and cara_bayar in ('Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit'))
  )
);
create index if not exists sales_store_idx on public.sales(store_id, tanggal);

create table if not exists public.competitor_sales (
  store_id int not null references public.stores(id),
  tanggal date not null,
  brand_id int not null references public.competitor_brands(id),
  unit int not null default 0 check (unit >= 0),
  diinput_oleh uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, tanggal, brand_id)
);

-- Stok pagi (batas 11.00 WIB). waktu_input = jam input pertama, tidak berubah saat dikoreksi.
create table if not exists public.stock_daily (
  store_id int not null references public.stores(id),
  tanggal date not null,
  product_id int not null references public.products(id),
  qty int not null default 0 check (qty >= 0),
  diinput_oleh uuid references public.profiles(id),
  waktu_input timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, tanggal, product_id)
);

create table if not exists public.display_checks (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  pc_id uuid references public.profiles(id),
  item_id int not null references public.checklist_items(id),
  ok boolean not null default true,
  created_at timestamptz not null default now(),
  unique (store_id, tanggal, item_id)
);

create table if not exists public.competitor_prices (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  brand_id int not null references public.competitor_brands(id),
  tipe_kompetitor text not null,
  tipe_oppo_pembanding text,
  harga_normal bigint check (harga_normal >= 0),
  harga_promo bigint check (harga_promo >= 0),
  keterangan text,
  diinput_oleh uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists competitor_prices_idx on public.competitor_prices(store_id, tanggal);

-- Laporan nihil (tidak ada penjualan / kompetitor 0 hari itu)
create table if not exists public.checkins (
  store_id int not null references public.stores(id),
  tanggal date not null,
  modul text not null check (modul in ('penjualan', 'kompetitor')),
  oleh uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (store_id, tanggal, modul)
);

-- Laporan malam terkirim (batas 22.00 WIB)
create table if not exists public.daily_reports (
  store_id int not null references public.stores(id),
  tanggal date not null,
  pc_id uuid references public.profiles(id),
  dikirim_oleh uuid references public.profiles(id),
  dikirim_pada timestamptz not null default now(),
  catatan text,                                  -- alasan jika dilengkapi TL/Trainer
  primary key (store_id, tanggal)
);

-- Istirahat (hanya jika PC keluar toko): 1 jam atau 2 jam, selfie saat mulai & kembali
create table if not exists public.breaks (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid not null references public.profiles(id),
  tanggal date not null,
  durasi_menit int not null check (durasi_menit in (60, 120)),
  mulai timestamptz not null default now(),
  photo_mulai_id uuid,
  jarak_mulai_m int,
  selesai timestamptz,
  photo_kembali_id uuid,
  jarak_kembali_m int,
  terlambat_menit int,
  flag text check (flag in ('terlambat', 'tidak_klik_kembali')),
  peringatan_pada timestamptz,
  unique (pc_id, tanggal)
);

create table if not exists public.store_visits (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  tanggal date not null,
  oleh uuid not null references public.profiles(id),
  jenis text not null check (jenis in ('kunjungan', 'training')),
  pc_id uuid references public.profiles(id),
  temuan text,
  tindak_lanjut text,
  created_at timestamptz not null default now()
);

-- Foto bukti (selfie istirahat, display, kunjungan). File di bucket "bukti", folder = store_id.
create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid references public.profiles(id),
  ref_tabel text not null check (ref_tabel in ('breaks', 'display_checks', 'store_visits')),
  ref_id uuid not null,
  path text not null,
  sumber text not null check (sumber in ('kamera', 'galeri')),
  waktu_ambil timestamptz,
  latitude double precision,
  longitude double precision,
  jarak_toko_m int,
  metadata_valid boolean,
  flags text[] not null default '{}',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists photos_ref_idx on public.photos(ref_id);

-- Offday / izin: PC full off seharian. Tanggal tanpa baris = hari kerja.
create table if not exists public.pc_day_status (
  pc_id uuid not null references public.profiles(id) on delete cascade,
  tanggal date not null,
  status text not null check (status in ('offday', 'izin')),
  dibuat_oleh uuid references public.profiles(id),
  dibuat_pada timestamptz not null default now(),
  primary key (pc_id, tanggal)
);

-- Target bulanan per toko. bulan = tanggal 1 bulan tersebut.
create table if not exists public.store_targets (
  store_id int not null references public.stores(id) on delete cascade,
  bulan date not null check (extract(day from bulan) = 1),
  jenis text not null check (jenis in ('unit', 'value', 'fokus_a7pro', 'fokus_reno16', 'iot')),
  nilai numeric not null default 0 check (nilai >= 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, bulan, jenis)
);

-- Riwayat perubahan produk, harga, dan target
create table if not exists public.audit_log (
  id bigserial primary key,
  tabel text not null,
  ref text not null,
  aksi text not null,
  nilai_lama jsonb,
  nilai_baru jsonb,
  oleh uuid references public.profiles(id),
  waktu timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. FUNGSI BANTU
-- ---------------------------------------------------------------------
create or replace function public.my_profile_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.my_store_id() returns int
language sql stable security definer set search_path = public as $$
  select store_id from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.my_area_id() returns int
language sql stable security definer set search_path = public as $$
  select area_id from public.profiles where auth_uid = auth.uid() and aktif
$$;

create or replace function public.is_pic() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'pic', false)
$$;

create or replace function public.today_wib() returns date
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

create or replace function public.time_wib() returns time
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::time $$;

create or replace function public.to_wib(ts timestamptz) returns date
language sql stable as $$ select (ts at time zone 'Asia/Jakarta')::date $$;

create or replace function public.server_now() returns timestamptz
language sql stable as $$ select now() $$;

create or replace function public.store_area(p_store int) returns int
language sql stable security definer set search_path = public as $$
  select area_id from public.stores where id = p_store
$$;

create or replace function public.store_has_pc(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select punya_pc from public.stores where id = p_store), false)
$$;

-- Semua PC aktif di toko itu sedang offday/izin pada tanggal tersebut
create or replace function public.store_pc_off(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.store_id = p_store and p.role = 'pc' and p.aktif)
     and not exists (
       select 1 from public.profiles p
        where p.store_id = p_store and p.role = 'pc' and p.aktif
          and not exists (select 1 from public.pc_day_status d where d.pc_id = p.id and d.tanggal = p_tanggal))
$$;

create or replace function public.pc_store(p_pc uuid) returns int
language sql stable security definer set search_path = public as $$
  select store_id from public.profiles where id = p_pc
$$;

-- Boleh melihat data toko: PIC semua, TL/Trainer areanya, PC tokonya
create or replace function public.can_view_store(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.my_role()
           when 'pic' then true
           when 'tl' then public.store_area(p_store) = public.my_area_id()
           when 'trainer' then public.store_area(p_store) = public.my_area_id()
           when 'pc' then p_store = public.my_store_id()
           else false
         end
$$;

-- Boleh mengatur toko (target, offday, akun PC, titik GPS): PIC semua, Trainer areanya
create or replace function public.can_manage_store(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_pic()
      or (public.my_role() = 'trainer' and public.store_area(p_store) = public.my_area_id())
$$;

-- Penjualan: PC tokonya, TL areanya, PIC semua. Tanggal lampau boleh, tanggal depan tidak.
create or replace function public.can_write_sales(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select p_tanggal <= public.today_wib() and (
           public.is_pic()
        or (public.my_role() = 'pc' and p_store = public.my_store_id())
        or (public.my_role() = 'tl' and public.store_area(p_store) = public.my_area_id()))
$$;

-- Stok, kompetitor, display, laporan malam:
--   PC: tokonya, hari ini, sebelum 22.00 WIB
--   TL/Trainer: areanya, untuk toko non PC, PC offday, atau PC tidak lapor (lewat 22.00 / tanggal lampau)
create or replace function public.can_write_daily(p_store int, p_tanggal date) returns boolean
language sql stable security definer set search_path = public as $$
  select p_tanggal <= public.today_wib() and (
           public.is_pic()
        or (public.my_role() = 'pc' and p_store = public.my_store_id()
              and p_tanggal = public.today_wib() and public.time_wib() < time '22:00')
        or (public.my_role() in ('tl', 'trainer') and public.store_area(p_store) = public.my_area_id()
              and (not public.store_has_pc(p_store)
                   or public.store_pc_off(p_store, p_tanggal)
                   or p_tanggal < public.today_wib()
                   or public.time_wib() >= time '22:00')))
$$;

create or replace function public.safe_int(t text) returns int
language sql immutable as $$ select case when t ~ '^[0-9]{1,9}$' then t::int end $$;

-- ---------------------------------------------------------------------
-- 4. TRIGGER
-- ---------------------------------------------------------------------
-- Hubungkan akun login (auth.users) ke profil berdasarkan email
create or replace function public.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set auth_uid = new.id
   where lower(email) = lower(new.email) and auth_uid is null;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Penjualan: nama, grup, tipe, dan harga diambil dari master produk (harga tidak bisa diakali dari HP)
create or replace function public.fill_sale_from_product() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.products;
begin
  if new.product_id is not null and (tg_op = 'INSERT' or new.product_id is distinct from old.product_id) then
    select * into p from public.products where id = new.product_id;
    if p.id is null then raise exception 'Produk tidak ditemukan'; end if;
    new.nama_produk := p.nama;
    new.grup := p.grup;
    new.tipe := p.tipe;
    new.harga := p.harga;
  end if;
  if tg_op = 'INSERT' then
    new.diinput_oleh := coalesce(public.my_profile_id(), new.diinput_oleh);
    if new.pc_id is null and public.my_role() = 'pc' then new.pc_id := public.my_profile_id(); end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_sale_fill on public.sales;
create trigger trg_sale_fill before insert or update on public.sales
  for each row execute function public.fill_sale_from_product();

-- Log kontak memperbarui "terakhir dihubungi" dan status konsumen (sama dengan OS)
create or replace function public.on_contact_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.dihubungi then
    update public.contacts
       set last_contacted_at = greatest(coalesce(last_contacted_at, new.waktu), new.waktu), updated_at = now()
     where id = new.contact_id;
  end if;
  if new.status_baru is not null then
    update public.contacts set status = new.status_baru, updated_at = now() where id = new.contact_id;
  end if;
  return new;
end $$;

drop trigger if exists trg_contact_log on public.contact_logs;
create trigger trg_contact_log after insert on public.contact_logs
  for each row execute function public.on_contact_log();

-- Stok: jam input pertama tidak berubah saat dikoreksi
create or replace function public.keep_stock_first_input() returns trigger
language plpgsql as $$
begin
  new.waktu_input := old.waktu_input;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_stock_keep on public.stock_daily;
create trigger trg_stock_keep before update on public.stock_daily
  for each row execute function public.keep_stock_first_input();

-- Riwayat perubahan produk & target
create or replace function public.audit_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ref text;
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'products' then
      v_ref := old.id::text;
    else
      v_ref := old.store_id::text || '|' || old.bulan::text || '|' || old.jenis;
    end if;
    insert into public.audit_log (tabel, ref, aksi, nilai_lama, oleh)
    values (tg_table_name, v_ref, tg_op, to_jsonb(old), public.my_profile_id());
    return old;
  end if;

  if tg_table_name = 'products' then
    v_ref := coalesce(new.id::text, new.nama);
    new.diubah_oleh := public.my_profile_id();
    new.diubah_pada := now();
  else
    v_ref := new.store_id::text || '|' || new.bulan::text || '|' || new.jenis;
    new.updated_by := public.my_profile_id();
    new.updated_at := now();
  end if;
  insert into public.audit_log (tabel, ref, aksi, nilai_lama, nilai_baru, oleh)
  values (tg_table_name, v_ref, tg_op,
          case when tg_op = 'UPDATE' then to_jsonb(old) end,
          to_jsonb(new),
          public.my_profile_id());
  return new;
end $$;

drop trigger if exists trg_audit_products on public.products;
create trigger trg_audit_products before insert or update or delete on public.products
  for each row execute function public.audit_change();
drop trigger if exists trg_audit_targets on public.store_targets;
create trigger trg_audit_targets before insert or update or delete on public.store_targets
  for each row execute function public.audit_change();

-- Target TL = total target toko di areanya (termasuk Rajawali). Tidak disimpan, selalu dihitung.
create or replace view public.area_targets with (security_invoker = true) as
  select s.area_id, t.bulan, t.jenis, sum(t.nilai) as nilai
    from public.store_targets t join public.stores s on s.id = t.store_id
   group by s.area_id, t.bulan, t.jenis;

-- ---------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['retail_accounts', 'areas', 'stores', 'store_locations', 'profiles', 'products',
                           'competitor_brands', 'checklist_items', 'contacts', 'contact_logs', 'sales',
                           'competitor_sales', 'stock_daily', 'display_checks', 'competitor_prices', 'checkins',
                           'daily_reports', 'breaks', 'store_visits', 'photos', 'pc_day_status', 'store_targets',
                           'audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Master: semua pengguna login bisa baca; PIC bisa ubah semua
do $$
declare t text;
begin
  foreach t in array array['retail_accounts', 'areas', 'stores', 'store_locations', 'profiles', 'products',
                           'competitor_brands', 'checklist_items'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_pic', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_pic()) with check (public.is_pic())', t || '_pic', t);
  end loop;
end $$;

-- Trainer: tambah & ubah produk/harga, atur checklist, titik GPS toko di areanya
drop policy if exists products_trainer_ins on public.products;
create policy products_trainer_ins on public.products for insert to authenticated
  with check (public.my_role() = 'trainer');
drop policy if exists products_trainer_upd on public.products;
create policy products_trainer_upd on public.products for update to authenticated
  using (public.my_role() = 'trainer') with check (public.my_role() = 'trainer');
drop policy if exists checklist_items_trainer on public.checklist_items;
create policy checklist_items_trainer on public.checklist_items for all to authenticated
  using (public.my_role() = 'trainer') with check (public.my_role() = 'trainer');
drop policy if exists store_locations_trainer on public.store_locations;
create policy store_locations_trainer on public.store_locations for all to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

-- Trainer: tambah & ubah akun PC di areanya (bukan TL/Trainer/PIC)
drop policy if exists profiles_trainer_ins on public.profiles;
create policy profiles_trainer_ins on public.profiles for insert to authenticated
  with check (public.my_role() = 'trainer' and role = 'pc' and public.can_manage_store(store_id));
drop policy if exists profiles_trainer_upd on public.profiles;
create policy profiles_trainer_upd on public.profiles for update to authenticated
  using (public.my_role() = 'trainer' and role = 'pc' and public.can_manage_store(store_id))
  with check (public.my_role() = 'trainer' and role = 'pc' and public.can_manage_store(store_id));

-- Penjualan
drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated using (public.can_view_store(store_id));
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales for insert to authenticated
  with check (public.can_write_sales(store_id, tanggal));
drop policy if exists sales_update on public.sales;
create policy sales_update on public.sales for update to authenticated
  using (public.can_write_sales(store_id, tanggal)) with check (public.can_write_sales(store_id, tanggal));
drop policy if exists sales_delete on public.sales;
create policy sales_delete on public.sales for delete to authenticated
  using (public.can_write_sales(store_id, tanggal));

-- Data harian toko: stok, kompetitor, display, harga kompetitor, nihil, laporan malam
do $$
declare t text;
begin
  foreach t in array array['competitor_sales', 'stock_daily', 'display_checks', 'competitor_prices', 'checkins',
                           'daily_reports'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_view_store(store_id))', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.can_write_daily(store_id, tanggal)) with check (public.can_write_daily(store_id, tanggal))', t || '_write', t);
  end loop;
end $$;

-- Database konsumen: nomor HP hanya untuk PC pemilik, TL, Trainer, PIC
drop policy if exists contacts_select on public.contacts;
create policy contacts_select on public.contacts for select to authenticated
  using (pc_id = public.my_profile_id() or (public.my_role() <> 'pc' and public.can_view_store(store_id)));
drop policy if exists contacts_insert on public.contacts;
create policy contacts_insert on public.contacts for insert to authenticated
  with check (pc_id = public.my_profile_id() and store_id = public.my_store_id());
drop policy if exists contacts_update on public.contacts;
create policy contacts_update on public.contacts for update to authenticated
  using (pc_id = public.my_profile_id() or public.is_pic())
  with check (pc_id = public.my_profile_id() or public.is_pic());
drop policy if exists contacts_delete on public.contacts;
create policy contacts_delete on public.contacts for delete to authenticated
  using (pc_id = public.my_profile_id() or public.is_pic());

drop policy if exists contact_logs_select on public.contact_logs;
create policy contact_logs_select on public.contact_logs for select to authenticated
  using (pc_id = public.my_profile_id()
         or (public.my_role() <> 'pc' and public.can_view_store(public.pc_store(pc_id))));
drop policy if exists contact_logs_insert on public.contact_logs;
create policy contact_logs_insert on public.contact_logs for insert to authenticated
  with check (pc_id = public.my_profile_id()
              and exists (select 1 from public.contacts c where c.id = contact_id and c.pc_id = public.my_profile_id()));

-- Istirahat: dibaca sesuai cakupan; mulai/kembali lewat RPC (Tahap 1). PIC bisa koreksi.
drop policy if exists breaks_select on public.breaks;
create policy breaks_select on public.breaks for select to authenticated using (public.can_view_store(store_id));
drop policy if exists breaks_pic on public.breaks;
create policy breaks_pic on public.breaks for all to authenticated using (public.is_pic()) with check (public.is_pic());

-- Kunjungan / training: TL, Trainer, PIC di cakupannya; ubah hanya milik sendiri
drop policy if exists store_visits_select on public.store_visits;
create policy store_visits_select on public.store_visits for select to authenticated using (public.can_view_store(store_id));
drop policy if exists store_visits_insert on public.store_visits;
create policy store_visits_insert on public.store_visits for insert to authenticated
  with check (oleh = public.my_profile_id() and public.my_role() in ('tl', 'trainer', 'pic') and public.can_view_store(store_id));
drop policy if exists store_visits_change on public.store_visits;
create policy store_visits_change on public.store_visits for update to authenticated
  using (oleh = public.my_profile_id() or public.is_pic()) with check (oleh = public.my_profile_id() or public.is_pic());
drop policy if exists store_visits_delete on public.store_visits;
create policy store_visits_delete on public.store_visits for delete to authenticated
  using (oleh = public.my_profile_id() or public.is_pic());

-- Foto
drop policy if exists photos_select on public.photos;
create policy photos_select on public.photos for select to authenticated using (public.can_view_store(store_id));
drop policy if exists photos_insert on public.photos;
create policy photos_insert on public.photos for insert to authenticated
  with check (created_by = public.my_profile_id() and public.can_view_store(store_id));
drop policy if exists photos_delete on public.photos;
create policy photos_delete on public.photos for delete to authenticated
  using (created_by = public.my_profile_id() or public.is_pic());

-- Offday / izin: PC lihat miliknya, TL lihat areanya, Trainer & PIC atur
drop policy if exists pc_day_status_select on public.pc_day_status;
create policy pc_day_status_select on public.pc_day_status for select to authenticated
  using (pc_id = public.my_profile_id() or (public.my_role() <> 'pc' and public.can_view_store(public.pc_store(pc_id))));
drop policy if exists pc_day_status_manage on public.pc_day_status;
create policy pc_day_status_manage on public.pc_day_status for all to authenticated
  using (public.can_manage_store(public.pc_store(pc_id)))
  with check (public.can_manage_store(public.pc_store(pc_id)));

-- Target: lihat sesuai cakupan, atur Trainer (areanya) & PIC
drop policy if exists store_targets_select on public.store_targets;
create policy store_targets_select on public.store_targets for select to authenticated using (public.can_view_store(store_id));
drop policy if exists store_targets_manage on public.store_targets;
create policy store_targets_manage on public.store_targets for all to authenticated
  using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

-- Riwayat perubahan: PIC saja (ditulis oleh trigger)
drop policy if exists audit_log_pic on public.audit_log;
create policy audit_log_pic on public.audit_log for select to authenticated using (public.is_pic());

-- ---------------------------------------------------------------------
-- 6. PENYIMPANAN FILE
-- ---------------------------------------------------------------------
-- Foto bukti (privat). Path: <store_id>/<nama file>
insert into storage.buckets (id, name, public)
values ('bukti', 'bukti', false)
on conflict (id) do nothing;

drop policy if exists bukti_insert on storage.objects;
create policy bukti_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'bukti' and public.can_view_store(public.safe_int((storage.foldername(name))[1])));
drop policy if exists bukti_select on storage.objects;
create policy bukti_select on storage.objects for select to authenticated
  using (bucket_id = 'bukti' and public.can_view_store(public.safe_int((storage.foldername(name))[1])));
drop policy if exists bukti_delete on storage.objects;
create policy bukti_delete on storage.objects for delete to authenticated
  using (bucket_id = 'bukti' and (public.is_pic() or owner = auth.uid()));

-- APK untuk update di dalam aplikasi (publik, diisi GitHub Actions). Batas 50 MB (paket Free).
insert into storage.buckets (id, name, public, file_size_limit)
values ('apk', 'apk', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

-- ---------------------------------------------------------------------
-- 7. RPC (dipanggil aplikasi)
-- ---------------------------------------------------------------------
-- Daftar nama untuk layar login (boleh diakses sebelum login)
create or replace function public.list_login_profiles() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email,
           'toko', coalesce(s.nama, ''), 'area', coalesce(a.nama, sa.nama, ''),
           'sudah_daftar', p.auth_uid is not null)
         order by case p.role when 'pic' then 0 when 'trainer' then 1 when 'tl' then 2 else 3 end,
                  coalesce(a.nama, sa.nama), p.nama), '[]'::jsonb)
    from public.profiles p
    left join public.stores s on s.id = p.store_id
    left join public.areas sa on sa.id = s.area_id
    left join public.areas a on a.id = p.area_id
   where p.aktif
$$;
grant execute on function public.list_login_profiles() to anon, authenticated;

create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email,
           'store_id', p.store_id, 'toko', coalesce(s.nama, ''),
           'area_id', coalesce(p.area_id, s.area_id), 'area', coalesce(a.nama, sa.nama, ''),
           'store_lat', l.latitude, 'store_lng', l.longitude, 'radius_m', coalesce(l.radius_m, 100),
           'lokasi', coalesce((select jsonb_agg(jsonb_build_object('nama', x.nama_lokasi, 'lat', x.latitude,
                                                                     'lng', x.longitude, 'radius_m', x.radius_m) order by x.id)
                                 from public.store_locations x where x.store_id = p.store_id), '[]'::jsonb))
    from public.profiles p
    left join public.stores s on s.id = p.store_id
    left join public.areas sa on sa.id = s.area_id
    left join public.areas a on a.id = p.area_id
    left join lateral (select * from public.store_locations x where x.store_id = p.store_id order by x.id limit 1) l on true
   where p.auth_uid = auth.uid() and p.aktif
$$;

create or replace function public.set_fcm_token(p_token text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set fcm_token = p_token where auth_uid = auth.uid()
$$;

-- Reset password: PIC untuk semua akun selain PIC, Trainer untuk PC di areanya.
-- Akun login dihapus; pemilik membuat password baru saat login berikutnya.
create or replace function public.reset_password(p_profile uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v public.profiles;
begin
  select * into v from public.profiles where id = p_profile;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.role = 'pic' then raise exception 'Password PIC NKA diatur di Supabase'; end if;
  if not (public.is_pic() or (public.my_role() = 'trainer' and v.role = 'pc' and public.can_manage_store(v.store_id))) then
    raise exception 'Akses ditolak';
  end if;
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set auth_uid = null where id = p_profile;
end $$;

-- ---------------------------------------------------------------------
-- 8. DATA AWAL
-- ---------------------------------------------------------------------
insert into public.retail_accounts (nama) values ('Erafone') on conflict (nama) do nothing;

insert into public.areas (nama) values ('Palangkaraya'), ('Sampit'), ('Pangkalanbun')
on conflict (nama) do nothing;

insert into public.stores (nama, retail_account_id, area_id, punya_pc)
select v.nama, r.id, a.id, v.punya_pc
  from (values
    ('Erafone Seth Adji', 'Palangkaraya', true),
    ('Erafone RTA Milono', 'Palangkaraya', true),
    ('Erafone G-Obos', 'Palangkaraya', true),
    ('Erafone Dutamall PKY', 'Palangkaraya', true),
    ('Erafone Rajawali', 'Palangkaraya', false),
    ('Erafone Pelita', 'Sampit', true),
    ('Erafone MT Haryono', 'Sampit', true),
    ('Erafone Pangkalanbun', 'Pangkalanbun', true)
  ) as v(nama, area, punya_pc)
  join public.areas a on a.nama = v.area
  join public.retail_accounts r on r.nama = 'Erafone'
on conflict (nama) do nothing;

insert into public.store_locations (store_id, nama_lokasi, latitude, longitude)
select s.id, v.lokasi, v.lat, v.lng
  from (values
    ('Erafone Seth Adji', 'Seth Adji', -2.219831, 113.930939),
    ('Erafone RTA Milono', 'RTA Milono', -2.223221, 113.919836),
    ('Erafone G-Obos', 'G-Obos', -2.222900, 113.906434),
    ('Erafone Dutamall PKY', 'Dutamall PKY', -2.247389, 113.922835),
    ('Erafone Rajawali', 'Rajawali', -2.190112, 113.892349),
    ('Erafone Pelita', 'Pelita', -2.548295, 112.950627),
    ('Erafone MT Haryono', 'MT Haryono', -2.541091, 112.950843),
    ('Erafone Pangkalanbun', 'Antasari', -2.675471, 111.637740),
    ('Erafone Pangkalanbun', 'Pakunegara', -2.672934, 111.635128)
  ) as v(toko, lokasi, lat, lng)
  join public.stores s on s.nama = v.toko
on conflict (store_id, nama_lokasi) do nothing;

-- Akun. Email hanya dipakai di belakang layar; pengguna cukup memilih nama di layar login.
insert into public.profiles (nama, role, store_id, area_id, email)
select v.nama, v.role, s.id, a.id, v.email
  from (values
    -- PC
    ('Indra Aryudi', 'pc', 'Erafone Seth Adji', null, 'indra@dailyreportnka.app'),
    ('Ahmad Syafiq', 'pc', 'Erafone RTA Milono', null, 'syafiq@dailyreportnka.app'),
    ('Muhammad Syaufi', 'pc', 'Erafone G-Obos', null, 'syaufi@dailyreportnka.app'),
    ('Nursuci Latifatu Solehah', 'pc', 'Erafone Dutamall PKY', null, 'nursuci@dailyreportnka.app'),
    ('Era Novallisti', 'pc', 'Erafone Pelita', null, 'era@dailyreportnka.app'),
    ('Nuriyah', 'pc', 'Erafone MT Haryono', null, 'nuriyah@dailyreportnka.app'),
    ('Utin Amelia Putri Dewi', 'pc', 'Erafone Pangkalanbun', null, 'utin@dailyreportnka.app'),
    -- TL
    ('Alwisiuts Jati Kurniawan', 'tl', null, 'Palangkaraya', 'alwisiuts@dailyreportnka.app'),
    ('Wiga Bintang Pratama', 'tl', null, 'Sampit', 'wiga@dailyreportnka.app'),
    ('Yanah', 'tl', null, 'Pangkalanbun', 'yanah@dailyreportnka.app'),
    -- Trainer
    ('Istihanah', 'trainer', null, 'Palangkaraya', 'istihanah@dailyreportnka.app'),
    ('Brandon Cahyadita', 'trainer', null, 'Sampit', 'brandon@dailyreportnka.app'),
    ('Elsa Permata Sari', 'trainer', null, 'Pangkalanbun', 'elsa@dailyreportnka.app'),
    -- PIC NKA
    ('Jenni Wijaya', 'pic', null, null, 'pic@dailyreportnka.app')
  ) as v(nama, role, toko, area, email)
  left join public.stores s on s.nama = v.toko
  left join public.areas a on a.nama = v.area
on conflict (email) do nothing;

-- Hubungkan akun yang mungkin sudah dibuat sebelum skrip ini dijalankan
update public.profiles p set auth_uid = u.id
  from auth.users u
 where lower(u.email) = lower(p.email) and p.auth_uid is null;

insert into public.competitor_brands (nama, urutan)
select * from (values
  ('vivo', 1), ('Samsung', 2), ('realme', 3), ('Infinix', 4), ('Xiaomi', 5), ('Tecno', 6),
  ('itel', 7), ('Huawei', 8), ('Apple', 9), ('Honor', 10), ('Advan', 11), ('Lainnya', 99)
) as v(nama, urutan)
on conflict (nama) do nothing;

insert into public.checklist_items (nama, keterangan, urutan)
select * from (values
  ('POSM terpasang', 'Poster, wobbler, dan materi promo OPPO terpasang rapi', 1),
  ('Dummy lengkap', 'Dummy / unit demo semua tipe tersedia dan menyala', 2),
  ('Harga terpasang', 'Label harga terpasang di setiap unit', 3)
) as v(nama, keterangan, urutan)
on conflict (nama) do nothing;

-- Master produk awal (daftar PIC NKA 10/11/2026). PIC & Trainer bisa menambah dan mengubah harga.
insert into public.products (tipe, nama, grup, harga, fokus, urutan)
select * from (values
  ('HP', 'A7 PRO 5G [6/256]', 'A Series', 7999000, 'A7 Pro', 1),
  ('HP', 'A7 PRO MAX 5G [8/256]', 'A Series', 9999000, 'A7 Pro', 2),
  ('HP', 'A6X [4/64]', 'A Series', 2299000, null, 3),
  ('HP', 'A6X [4/128]', 'A Series', 2899000, null, 4),
  ('HP', 'A6X [6/128]', 'A Series', 3599000, null, 5),
  ('HP', 'A6X [8/128]', 'A Series', 3899000, null, 6),
  ('HP', 'A6X [6/256]', 'A Series', 3999000, null, 7),
  ('HP', 'A6C [4/64]', 'A Series', 2799000, null, 8),
  ('HP', 'A6C [4/128]', 'A Series', 3199000, null, 9),
  ('HP', 'A6 [6/128]', 'A Series', 4299000, null, 10),
  ('HP', 'A6 [6/256]', 'A Series', 4799000, null, 11),
  ('HP', 'A6S [8/128]', 'A Series', 4999000, null, 12),
  ('HP', 'A6S [8/256]', 'A Series', 5499000, null, 13),
  ('HP', 'A6 PRO 4G [8/128]', 'A Series', 4599000, null, 14),
  ('HP', 'A6 PRO 4G [8/256]', 'A Series', 4999000, null, 15),
  ('HP', 'A6 PRO 5G [8/256]', 'A Series', 5299000, null, 16),
  ('HP', 'RENO 16 F 5G [8/128]', 'Reno Series', 7999000, 'Reno 16', 17),
  ('HP', 'RENO 16 F 5G [8/256]', 'Reno Series', 8699000, 'Reno 16', 18),
  ('HP', 'RENO 16 5G [8/256]', 'Reno Series', 11999000, 'Reno 16', 19),
  ('HP', 'RENO 16 5G [12/256]', 'Reno Series', 12999000, 'Reno 16', 20),
  ('HP', 'RENO 16 PRO 5G [12/256]', 'Reno Series', 14999000, 'Reno 16', 21),
  ('HP', 'RENO 15 F 5G [8/128]', 'Reno Series', 6599000, null, 22),
  ('HP', 'RENO 15 F 5G [8/256]', 'Reno Series', 7199000, null, 23),
  ('HP', 'RENO 15 F 5G [12/256]', 'Reno Series', 7899000, null, 24),
  ('HP', 'RENO 15 5G [8/256]', 'Reno Series', 9299000, null, 25),
  ('HP', 'RENO 15 5G [12/256]', 'Reno Series', 9999000, null, 26),
  ('HP', 'RENO 15 PRO MAX [12/512]', 'Reno Series', 14499000, null, 27),
  ('HP', 'FIND X10 [12/512]', 'Find Series', 20999000, null, 28),
  ('HP', 'FIND X9 [12/256]', 'Find Series', 15999000, null, 29),
  ('HP', 'FIND X9 [16/512]', 'Find Series', 17999000, null, 30),
  ('HP', 'FIND X9 PRO [16/512]', 'Find Series', 20999000, null, 31),
  ('HP', 'FIND X9S [12/256]', 'Find Series', 15499000, null, 32),
  ('HP', 'FIND X9S [12/512]', 'Find Series', 17499000, null, 33),
  ('HP', 'FIND X9 ULTRA [12/512]', 'Find Series', 25999000, null, 34),
  ('HP', 'FIND X9 ULTRA [16/1TB]', 'Find Series', 31999000, null, 35),
  ('HP', 'FIND N5 FOLD', 'Find Series', 27999000, null, 36),
  ('IOT', 'OPPO Pad 3 Matte Display', 'Pad', 8999000, null, 101),
  ('IOT', 'OPPO PAD 5 Matte Display Edition 256GB 8GB Star', 'Pad', 7999000, null, 102),
  ('IOT', 'PAD2 8+256GB', 'Pad', 6999000, null, 103),
  ('IOT', 'OPPO Pad Neo', 'Pad', 4599000, null, 104),
  ('IOT', 'PAD AIR 4+128 Purple', 'Pad', 3599000, null, 105),
  ('IOT', 'OPPO Pad SE Matte Display Edition', 'Pad', 3599000, null, 106),
  ('IOT', 'PAD AIR 4+64 GREY', 'Pad', 2999000, null, 107),
  ('IOT', 'OPPO Watch X3 OWWE261 Misty Titanium', 'Watch', 6999000, null, 108),
  ('IOT', 'OPPO Watch X3 OWWE261 Obsidian Black', 'Watch', 6499000, null, 109),
  ('IOT', 'WATCH X2 OWWE251', 'Watch', 5999000, null, 110),
  ('IOT', 'WATCH X OWWE231', 'Watch', 4999000, null, 111),
  ('IOT', 'OPPO Watch X2 Mini OWWE242', 'Watch', 4499000, null, 112),
  ('IOT', 'OPPO Watch S Silver Gleam', 'Watch', 3099000, null, 113),
  ('IOT', 'OPPO Watch S Phantom Black', 'Watch', 2999000, null, 114),
  ('IOT', 'OPPO Watch S Air Silver', 'Watch', 2999000, null, 115),
  ('IOT', 'OPPO BAND 2', 'Band', 1099000, null, 116),
  ('IOT', 'OPPO BAND (BLACK PURPLE)', 'Band', 599000, null, 117),
  ('IOT', 'OPPO Enco Clip2 Open Earbuds1 ETEN1', 'Audio', 2899000, null, 118),
  ('IOT', 'Enco X3i', 'Audio', 1799000, null, 119),
  ('IOT', 'Enco X3s True Wireless Noise Cancelling', 'Audio', 1799000, null, 120),
  ('IOT', 'OPPO Bubble VBG06', 'Audio', 1499000, null, 121),
  ('IOT', 'OPPO Enco Air5s ETEF1', 'Audio', 1299000, null, 122),
  ('IOT', 'Enco Air2 Pro', 'Audio', 1099000, null, 123),
  ('IOT', 'OPPO Enco Air5 ETEP1', 'Audio', 899000, null, 124),
  ('IOT', 'OPPO Enco Air4', 'Audio', 799000, null, 125),
  ('IOT', 'Enco Air3', 'Audio', 799000, null, 126),
  ('IOT', 'OPPO Enco Air3i True Wireless', 'Audio', 599000, null, 127),
  ('IOT', 'ENCO BUDS2', 'Audio', 399000, null, 128),
  ('IOT', 'OPPO Enco Buds3 Pro', 'Audio', 349000, null, 129),
  ('IOT', 'OPPO Enco Buds3 True Wireless Earbuds E', 'Audio', 299000, null, 130)
) as v(tipe, nama, grup, harga, fokus, urutan)
on conflict (tipe, nama) do nothing;

select 'Daily Report NKA siap: ' || (select count(*) from public.stores) || ' toko, '
       || (select count(*) from public.profiles) || ' akun, '
       || (select count(*) from public.products) || ' produk, '
       || (select count(*) from public.competitor_brands) || ' brand' as status;
