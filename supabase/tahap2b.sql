-- =====================================================================
-- Daily Report NKA - Tahap 2b
--   1. MS Allbrand autosave (tanpa notifikasi setiap ketukan; notifikasi sekali saat selesai)
--   2. Kategori user penjualan: Walk-in / Databased / Online
--   3. Pengingat dari TL / Trainer / PIC ke PC (push ke HP PC)
-- Reset password PC oleh TL & Trainer area sudah ada sejak tahap1i.sql (fungsi reset_password).
-- Jalankan SETELAH tahap2a.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. MS ALLBRAND: simpan per hari. p_notif = false untuk autosave (tidak mengirim push),
--    p_notif = true saat PC menekan "Selesai" (satu push ke atasan).
-- ---------------------------------------------------------------------
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb, p_notif boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_ringkas text;
  v_total int;
begin
  if not public.can_write_daily(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. PC hanya bisa input hari ini sebelum 22.30 WIB.';
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
    public.label_aktor(v_me, p_store) || ': brand lain ' || v_total || ' unit hari ini'
      || coalesce(' (' || v_ringkas || ')', ' (tidak ada penjualan brand lain)'),
    p_tanggal, null);
end $$;

-- Versi lama (3 parameter) tetap ada untuk aplikasi lama: selalu kirim notifikasi.
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  select public.simpan_ms_allbrand(p_store, p_tanggal, p_detail, true)
$$;

-- ---------------------------------------------------------------------
-- 2. KATEGORI USER PENJUALAN
-- ---------------------------------------------------------------------
alter table public.sales add column if not exists kategori_user text;
alter table public.sales drop constraint if exists sales_kategori_user_check;
alter table public.sales add constraint sales_kategori_user_check
  check (kategori_user is null or kategori_user in ('Walk-in', 'Databased', 'Online'));

-- Notifikasi penjualan ikut menyebut kategori user
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
  else
    perform public.catat_aktivitas(old.store_id, public.my_profile_id(), 'hapus_penjualan', 'Penjualan dihapus',
      public.label_aktor(public.my_profile_id(), old.store_id) || ' menghapus ' || old.nama_produk || ' x' || old.qty
        || ' (' || to_char(old.tanggal, 'DD/MM') || ')',
      old.tanggal, old.id);
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- 3. PENGINGAT KE PC
-- ---------------------------------------------------------------------
create table if not exists public.pengingat (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid not null references public.profiles(id),
  dari uuid references public.profiles(id),
  modul text[] not null default '{}',
  pesan text not null,
  tanggal date not null default public.today_wib(),
  dibaca_pada timestamptz,
  push_pada timestamptz,
  push_ok boolean,
  created_at timestamptz not null default now()
);
create index if not exists pengingat_pc_idx on public.pengingat(pc_id, created_at desc);
create index if not exists pengingat_store_idx on public.pengingat(store_id, created_at desc);

alter table public.pengingat enable row level security;
drop policy if exists pengingat_select on public.pengingat;
create policy pengingat_select on public.pengingat for select to authenticated
  using (public.can_view_store(store_id));

-- Label modul untuk isi pesan
create or replace function public.label_modul(p text) returns text
language sql immutable as $$
  select case p
    when 'stok' then 'update stok'
    when 'penjualan' then 'input penjualan'
    when 'ms_allbrand' then 'isi MS Allbrand'
    when 'display' then 'cek display'
    when 'sosmed' then 'activity sosmed'
    when 'leasing' then 'cek limit leasing'
    when 'laporan' then 'kirim laporan'
    when 'istirahat' then 'kembali dari istirahat'
    else p end
$$;

-- TL / Trainer / PIC mengirim pengingat ke PC toko. Mengembalikan nama PC dan status HP terdaftar.
create or replace function public.kirim_pengingat(p_store int, p_modul text[], p_pesan text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_pc public.profiles;
  v_pesan text;
  v_id uuid;
begin
  if public.my_role() not in ('tl', 'trainer', 'pic') or not public.can_view_store(p_store) then
    raise exception 'Akses ditolak';
  end if;
  select * into v_pc from public.profiles
   where store_id = p_store and role = 'pc' and aktif order by created_at limit 1;
  if v_pc.id is null then raise exception 'Toko ini belum punya PC'; end if;
  if coalesce(array_length(p_modul, 1), 0) = 0 and coalesce(trim(p_pesan), '') = '' then
    raise exception 'Pilih minimal satu kegiatan atau tulis pesan';
  end if;

  v_pesan := case when coalesce(array_length(p_modul, 1), 0) > 0
                  then 'Segera ' || (select string_agg(public.label_modul(m), ', ') from unnest(p_modul) m) || '.'
                  else '' end
             || case when coalesce(trim(p_pesan), '') <> '' then ' ' || trim(p_pesan) else '' end;

  insert into public.pengingat (store_id, pc_id, dari, modul, pesan)
  values (p_store, v_pc.id, v_me, coalesce(p_modul, '{}'), trim(v_pesan))
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'pc', v_pc.nama, 'punya_hp', v_pc.fcm_token is not null);
end $$;

-- PC menandai pengingat sudah dibaca
create or replace function public.baca_pengingat(p_id uuid default null) returns void
language sql security definer set search_path = public as $$
  update public.pengingat set dibaca_pada = now()
   where pc_id = public.my_profile_id() and dibaca_pada is null and (p_id is null or id = p_id)
$$;

-- Push ke HP PC lewat edge function kirim-notif
create or replace function public.ev_pengingat_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform net.http_post(
      url := 'https://stsuljrjjnjeqixetcqf.supabase.co/functions/v1/kirim-notif',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('pengingat_id', new.id)
    );
  exception when others then
    null;
  end;
  return null;
end $$;
drop trigger if exists trg_pengingat_push on public.pengingat;
create trigger trg_pengingat_push after insert on public.pengingat for each row execute function public.ev_pengingat_push();

-- Realtime: PC yang sedang membuka aplikasi langsung melihat pengingat baru
do $$ begin
  alter publication supabase_realtime add table public.pengingat;
exception when others then null;
end $$;

select 'Tahap 2b siap' as status,
       (select count(*) from information_schema.columns where table_name = 'sales' and column_name = 'kategori_user') as kolom_kategori,
       (select count(*) from pg_proc where proname = 'simpan_ms_allbrand') as versi_ms_allbrand;
