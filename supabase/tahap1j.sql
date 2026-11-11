-- =====================================================================
-- Daily Report NKA - Status online & riwayat login
-- Aplikasi mengirim tanda aktif setiap 2 menit selama dibuka. Dashboard TL, Trainer, PIC:
--   hijau = aplikasi PC terbuka dalam 5 menit terakhir (online)
--   merah = tidak online / sudah keluar / belum pernah login
-- Riwayat login & keluar tersimpan di tabel login_log.
-- Jalankan SETELAH tahap1i.sql. Aman dijalankan ulang.
-- =====================================================================

alter table public.profiles add column if not exists last_seen timestamptz;
alter table public.profiles add column if not exists last_login timestamptz;
alter table public.profiles add column if not exists logged_in boolean not null default false;

create table if not exists public.login_log (
  id bigserial primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  jenis text not null check (jenis in ('login', 'logout', 'buka')),
  waktu timestamptz not null default now()
);
create index if not exists login_log_profile_idx on public.login_log(profile_id, waktu desc);

alter table public.login_log enable row level security;
drop policy if exists login_log_select on public.login_log;
create policy login_log_select on public.login_log for select to authenticated
  using (profile_id = public.my_profile_id()
         or public.is_pic()
         or (public.my_role() in ('tl', 'trainer')
             and exists (select 1 from public.profiles p
                          where p.id = profile_id and p.role = 'pc' and public.can_view_store(p.store_id))));

-- Tanda aktif (dipanggil aplikasi setiap 2 menit selama dibuka)
create or replace function public.ping_online() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_seen = now(), logged_in = true where auth_uid = auth.uid()
$$;

-- Dipanggil setelah login berhasil (jenis 'login') atau saat aplikasi dibuka dengan sesi tersimpan ('buka')
create or replace function public.catat_login(p_jenis text default 'login') returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.my_profile_id();
begin
  if v is null then return; end if;
  update public.profiles
     set last_seen = now(), logged_in = true,
         last_login = case when p_jenis = 'login' then now() else last_login end
   where id = v;
  -- "buka" dicatat paling banyak sekali per 30 menit agar riwayat tidak penuh
  if p_jenis = 'login' or not exists (
       select 1 from public.login_log where profile_id = v and waktu > now() - interval '30 minutes') then
    insert into public.login_log (profile_id, jenis) values (v, case when p_jenis = 'login' then 'login' else 'buka' end);
  end if;
end $$;

-- Dipanggil sebelum keluar (logout)
create or replace function public.catat_logout() returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public.my_profile_id();
begin
  if v is null then return; end if;
  update public.profiles set logged_in = false, last_seen = now() where id = v;
  insert into public.login_log (profile_id, jenis) values (v, 'logout');
end $$;

-- Login dihapus oleh reset password / hapus PC: tandai tidak login
create or replace function public.on_auth_uid_null() returns trigger
language plpgsql as $$
begin
  if new.auth_uid is null and old.auth_uid is not null then new.logged_in := false; end if;
  return new;
end $$;
drop trigger if exists trg_auth_uid_null on public.profiles;
create trigger trg_auth_uid_null before update of auth_uid on public.profiles
  for each row execute function public.on_auth_uid_null();

select 'Status online & riwayat login siap' as status;
