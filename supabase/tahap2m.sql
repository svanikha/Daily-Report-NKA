-- =====================================================================
-- Daily Report NKA - Tahap 2m: jenis activity bisa ditambah + kewajiban activity per area
--   1. Jenis activity (FB Marketplace, TikTok Live, IG story, WA story, dan activity baru buatan atasan).
--      TL / Trainer: menambah activity untuk areanya. PIC / Manajer Trainer: semua area atau area tertentu.
--   2. Kewajiban HARIAN per area: target tiap activity + cek limit (total / per leasing).
--      Palangkaraya, Sampit, Pangkalanbun bisa berbeda.
-- Jalankan SETELAH tahap2l.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. JENIS ACTIVITY
-- ---------------------------------------------------------------------
create table if not exists public.jenis_activity (
  kode text primary key,
  nama text not null,
  satuan text not null default 'kali',
  area_id int references public.areas(id) on delete cascade,   -- null = semua area
  aktif boolean not null default true,
  urutan int not null default 100,
  dibuat_oleh uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.jenis_activity enable row level security;
drop policy if exists jenis_activity_read on public.jenis_activity;
create policy jenis_activity_read on public.jenis_activity for select to authenticated using (true);

insert into public.jenis_activity (kode, nama, satuan, urutan) values
  ('fb_posting', 'FB Marketplace - Posting', 'kali', 1),
  ('tiktok_live', 'TikTok - Live', 'kali', 2),
  ('ig_story', 'Instagram - Update story', 'kali', 3),
  ('wa_story', 'WhatsApp - Update story', 'kali', 4)
on conflict (kode) do nothing;

-- Activity PC boleh memakai jenis apa pun yang terdaftar
alter table public.social_activities drop constraint if exists social_activities_kode_check;
do $$ begin
  alter table public.social_activities add constraint social_activities_kode_fkey
    foreign key (kode) references public.jenis_activity(kode);
exception when duplicate_object then null;
end $$;

-- Tambah (p_kode null) atau ubah jenis activity
create or replace function public.simpan_jenis_activity(p_kode text, p_nama text, p_satuan text, p_area int)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v public.jenis_activity;
  v_kode text;
begin
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama activity wajib diisi'; end if;
  if public.my_role() not in ('tl', 'trainer', 'pic') then raise exception 'Akses ditolak'; end if;
  -- TL / Trainer hanya untuk areanya
  if not public.is_pic() and (p_area is null or p_area <> public.my_area_id()) then
    raise exception 'TL / Trainer hanya bisa mengatur activity untuk areanya';
  end if;
  if p_kode is null then
    v_kode := 'act_' || substr(md5(random()::text || clock_timestamp()::text), 1, 8);
    insert into public.jenis_activity (kode, nama, satuan, area_id, urutan, dibuat_oleh)
    values (v_kode, trim(p_nama), coalesce(nullif(trim(p_satuan), ''), 'kali'), p_area,
            100 + (select count(*) from public.jenis_activity), public.my_profile_id());
    return v_kode;
  end if;
  select * into v from public.jenis_activity where kode = p_kode;
  if v.kode is null then raise exception 'Activity tidak ditemukan'; end if;
  if not public.is_pic() and (v.area_id is null or v.area_id <> public.my_area_id()) then
    raise exception 'Activity ini diatur oleh PIC NKA';
  end if;
  update public.jenis_activity
     set nama = trim(p_nama), satuan = coalesce(nullif(trim(p_satuan), ''), 'kali'),
         area_id = case when public.is_pic() then p_area else v.area_id end, aktif = true
   where kode = p_kode;
  return p_kode;
end $$;

-- Nonaktifkan jenis activity (riwayat lama tetap tersimpan)
create or replace function public.hapus_jenis_activity(p_kode text) returns void
language plpgsql security definer set search_path = public as $$
declare v public.jenis_activity;
begin
  select * into v from public.jenis_activity where kode = p_kode;
  if v.kode is null then raise exception 'Activity tidak ditemukan'; end if;
  if not (public.is_pic() or (public.my_role() in ('tl', 'trainer') and v.area_id = public.my_area_id())) then
    raise exception 'Activity ini diatur oleh PIC NKA';
  end if;
  update public.jenis_activity set aktif = false where kode = p_kode;
  delete from public.kewajiban_activity where kode = p_kode;
end $$;

-- ---------------------------------------------------------------------
-- 2. KEWAJIBAN ACTIVITY PER AREA (target harian)
--    Kode: kode jenis_activity, 'cek_limit' (semua leasing), atau 'cek:<Leasing>' (misal cek:Avanto)
-- ---------------------------------------------------------------------
create table if not exists public.kewajiban_activity (
  area_id int not null references public.areas(id) on delete cascade,
  kode text not null,
  target int not null check (target > 0),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (area_id, kode)
);
alter table public.kewajiban_activity drop constraint if exists kewajiban_activity_kode_check;
alter table public.kewajiban_activity enable row level security;
drop policy if exists kewajiban_activity_read on public.kewajiban_activity;
create policy kewajiban_activity_read on public.kewajiban_activity for select to authenticated using (true);

-- Simpan semua kewajiban satu area sekaligus. p_items: {"fb_posting": 2, "cek:Avanto": 1, ...}. 0 = tidak wajib.
create or replace function public.simpan_kewajiban(p_area int, p_items jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_manage_area(p_area) then raise exception 'Area ini di luar wewenang kamu'; end if;
  delete from public.kewajiban_activity where area_id = p_area;
  insert into public.kewajiban_activity (area_id, kode, target, updated_by)
  select p_area, e.key, (e.value)::text::int, public.my_profile_id()
    from jsonb_each(coalesce(p_items, '{}'::jsonb)) e
   where coalesce((e.value)::text::int, 0) > 0;
end $$;

-- Status kewajiban satu toko pada satu tanggal: target vs capaian
create or replace function public.kewajiban_status(p_store int, p_tanggal date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'kode', k.kode, 'target', k.target,
           'nama', case when k.kode = 'cek_limit' then 'Cek limit (semua leasing)'
                        when k.kode like 'cek:%' then 'Cek limit ' || substr(k.kode, 5)
                        else coalesce(j.nama, k.kode) end,
           'satuan', case when k.kode like 'cek%' then 'pengajuan' else coalesce(j.satuan, 'kali') end,
           'capai', case
             when k.kode = 'cek_limit' then
               (select count(*) from public.leasing_checks where store_id = p_store and tanggal = p_tanggal)
             when k.kode like 'cek:%' then
               (select count(*) from public.leasing_checks
                 where store_id = p_store and tanggal = p_tanggal and leasing = substr(k.kode, 5))
             else
               coalesce((select sum(jumlah) from public.social_activities
                          where store_id = p_store and tanggal = p_tanggal and kode = k.kode), 0)
           end)
         order by case when k.kode like 'cek%' then 1 else 0 end, coalesce(j.urutan, 999), k.kode), '[]'::jsonb)
    from public.kewajiban_activity k
    left join public.jenis_activity j on j.kode = k.kode
   where k.area_id = public.store_area(p_store)
     and (j.kode is null or j.aktif)
     and public.can_view_store(p_store)
$$;

select 'Jenis & kewajiban activity siap' as status;

-- Label activity di notifikasi mengikuti nama jenis activity
create or replace function public.sosmed_label(p_kode text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select nama from public.jenis_activity where kode = p_kode), p_kode)
$$;
