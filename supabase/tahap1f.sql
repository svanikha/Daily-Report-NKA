-- =====================================================================
-- Daily Report NKA - Activity: report sosmed & cek limit leasing (seperti Daily Report OS)
-- Jalankan SETELAH tahap1e.sql. Aman dijalankan ulang. Tidak ada data yang dihapus.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABEL
-- ---------------------------------------------------------------------
create table if not exists public.social_activities (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid references public.profiles(id),
  diinput_oleh uuid not null references public.profiles(id),   -- diisi otomatis oleh trigger
  tanggal date not null,
  kode text not null check (kode in ('fb_posting', 'tiktok_konten', 'tiktok_live', 'ig_story', 'wa_story')),
  jumlah int not null check (jumlah > 0),
  link text,
  created_at timestamptz not null default now()
);
create index if not exists social_activities_idx on public.social_activities(store_id, tanggal);

create table if not exists public.leasing_checks (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  pc_id uuid references public.profiles(id),
  diinput_oleh uuid not null references public.profiles(id),   -- diisi otomatis oleh trigger
  tanggal date not null,
  leasing text not null check (leasing in ('Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit')),
  hasil text not null check (hasil in ('Approve', 'Reject')),
  limit_disetujui bigint,
  created_at timestamptz not null default now(),
  check (hasil = 'Reject' or coalesce(limit_disetujui, 0) > 0)
);
create index if not exists leasing_checks_idx on public.leasing_checks(store_id, tanggal);

-- Pelaku diisi dari akun yang login (tidak bisa diakali dari HP)
create or replace function public.set_pelaku() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.diinput_oleh := coalesce(public.my_profile_id(), new.diinput_oleh);
  if new.pc_id is null and public.my_role() = 'pc' then new.pc_id := public.my_profile_id(); end if;
  return new;
end $$;
drop trigger if exists trg_pelaku_sosmed on public.social_activities;
create trigger trg_pelaku_sosmed before insert on public.social_activities for each row execute function public.set_pelaku();
drop trigger if exists trg_pelaku_leasing on public.leasing_checks;
create trigger trg_pelaku_leasing before insert on public.leasing_checks for each row execute function public.set_pelaku();

-- ---------------------------------------------------------------------
-- 2. HAK AKSES: sama dengan data harian toko lain
--    (PC: tokonya, hari ini, sebelum 22.00; TL/Trainer: toko non PC, PC offday, PC tidak lapor)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['social_activities', 'leasing_checks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_view_store(store_id))', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.can_write_daily(store_id, tanggal)) with check (public.can_write_daily(store_id, tanggal))', t || '_write', t);
  end loop;
end $$;

alter table public.photos drop constraint if exists photos_ref_tabel_check;
alter table public.photos add constraint photos_ref_tabel_check
  check (ref_tabel in ('breaks', 'display_checks', 'display_reports', 'store_visits', 'social_activities', 'leasing_checks'));

-- ---------------------------------------------------------------------
-- 3. NOTIFIKASI AKTIVITAS ke TL, Trainer, PIC
-- ---------------------------------------------------------------------
alter table public.aktivitas drop constraint if exists aktivitas_jenis_check;
alter table public.aktivitas add constraint aktivitas_jenis_check check (jenis in (
  'penjualan_hp', 'penjualan_iot', 'hapus_penjualan', 'nosell', 'stok', 'ms_allbrand', 'display',
  'laporan', 'istirahat_mulai', 'istirahat_selesai', 'istirahat_telat', 'sosmed', 'leasing'));

create or replace function public.sosmed_label(p_kode text) returns text
language sql immutable as $$
  select case p_kode
    when 'fb_posting' then 'FB Marketplace - Posting'
    when 'tiktok_konten' then 'TikTok - Konten diupload'
    when 'tiktok_live' then 'TikTok - Live'
    when 'ig_story' then 'Instagram - Update story'
    when 'wa_story' then 'WhatsApp - Update story'
    else p_kode end
$$;

create or replace function public.ev_sosmed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.catat_aktivitas(new.store_id, new.diinput_oleh, 'sosmed', 'Report sosmed',
    public.label_aktor(new.diinput_oleh, new.store_id) || ': ' || public.sosmed_label(new.kode) || ' x' || new.jumlah
      || coalesce(' · ' || new.link, ''),
    new.tanggal, new.id);
  return null;
end $$;
drop trigger if exists trg_ev_sosmed on public.social_activities;
create trigger trg_ev_sosmed after insert on public.social_activities for each row execute function public.ev_sosmed();

create or replace function public.ev_leasing() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.catat_aktivitas(new.store_id, new.diinput_oleh, 'leasing', 'Cek limit ' || new.leasing,
    public.label_aktor(new.diinput_oleh, new.store_id) || ': ' || new.leasing || ' · ' || new.hasil
      || case when new.hasil = 'Approve' then ' · limit ' || public.rp(new.limit_disetujui) else '' end,
    new.tanggal, new.id);
  return null;
end $$;
drop trigger if exists trg_ev_leasing on public.leasing_checks;
create trigger trg_ev_leasing after insert on public.leasing_checks for each row execute function public.ev_leasing();

-- ---------------------------------------------------------------------
-- 4. REKAP ACTIVITY satu toko (hari ini & bulan berjalan) untuk dashboard dan gambar laporan
-- ---------------------------------------------------------------------
create or replace function public.rekap_activity(p_store int, p_tanggal date) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.can_view_store(p_store) then null else jsonb_build_object(
    'sosmed_hari', (select coalesce(jsonb_object_agg(kode, n), '{}'::jsonb)
                      from (select kode, sum(jumlah) n from public.social_activities
                             where store_id = p_store and tanggal = p_tanggal group by kode) x),
    'sosmed_bulan', (select coalesce(jsonb_object_agg(kode, n), '{}'::jsonb)
                       from (select kode, sum(jumlah) n from public.social_activities
                              where store_id = p_store and tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
                              group by kode) x),
    'leasing_hari', (select coalesce(jsonb_agg(jsonb_build_object('leasing', leasing, 'hasil', hasil, 'limit', limit_disetujui)
                                               order by created_at), '[]'::jsonb)
                       from public.leasing_checks where store_id = p_store and tanggal = p_tanggal),
    'leasing_bulan', (select jsonb_build_object('total', count(*), 'approve', count(*) filter (where hasil = 'Approve'),
                                                'reject', count(*) filter (where hasil = 'Reject'))
                        from public.leasing_checks
                       where store_id = p_store and tanggal between date_trunc('month', p_tanggal)::date and p_tanggal)
  ) end
$$;

select 'Activity sosmed & cek limit siap' as status;
