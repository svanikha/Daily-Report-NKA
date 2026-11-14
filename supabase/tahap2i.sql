-- =====================================================================
-- Daily Report NKA - Tahap 2i
--   1. Pesan / pengingat atasan ke PC bersifat PRIBADI: hanya pengirim dan PC penerima yang bisa
--      melihat. Balasan "Siap 👍" dikirim hanya ke pengirim (tidak lagi masuk Aktivitas semua atasan).
--   2. Pesan antar TL, Trainer, dan PIC NKA (chat pribadi 1 lawan 1) + push ke HP penerima.
-- Setelah menjalankan file ini, tempel ulang kode supabase/functions/kirim-notif/index.ts
-- ke edge function kirim-notif lalu Deploy.
-- Jalankan SETELAH tahap2h.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PENGINGAT PRIBADI
-- ---------------------------------------------------------------------
drop policy if exists pengingat_select on public.pengingat;
create policy pengingat_select on public.pengingat for select to authenticated
  using (pc_id = public.my_profile_id() or dari = public.my_profile_id());

create or replace function public.push_ke_kirim_notif(p_body jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform net.http_post(
      url := 'https://stsuljrjjnjeqixetcqf.supabase.co/functions/v1/kirim-notif',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := p_body
    );
  exception when others then
    null;
  end;
end $$;

-- Balasan PC: hanya pengirim pengingat yang diberi tahu (push langsung, tanpa Aktivitas)
create or replace function public.respon_pengingat(p_id uuid default null, p_respon text default 'Siap') returns int
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  r record;
  n int := 0;
begin
  for r in
    select g.id from public.pengingat g
     where g.pc_id = v_me and g.respon is null and (p_id is null or g.id = p_id)
     order by g.created_at
  loop
    update public.pengingat set respon = coalesce(nullif(trim(p_respon), ''), 'Siap'), respon_pada = now(),
                                dibaca_pada = coalesce(dibaca_pada, now())
     where id = r.id;
    perform public.push_ke_kirim_notif(jsonb_build_object('respon_pengingat', r.id));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 2. PESAN ANTAR ATASAN (TL, Trainer, PIC NKA)
-- ---------------------------------------------------------------------
create table if not exists public.pesan_atasan (
  id uuid primary key default gen_random_uuid(),
  dari uuid not null references public.profiles(id),
  ke uuid not null references public.profiles(id),
  isi text not null check (length(trim(isi)) > 0),
  dibaca_pada timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists pesan_atasan_ke_idx on public.pesan_atasan(ke, created_at desc);
create index if not exists pesan_atasan_dari_idx on public.pesan_atasan(dari, created_at desc);

alter table public.pesan_atasan enable row level security;
drop policy if exists pesan_atasan_select on public.pesan_atasan;
create policy pesan_atasan_select on public.pesan_atasan for select to authenticated
  using (dari = public.my_profile_id() or ke = public.my_profile_id());

do $$ begin
  alter publication supabase_realtime add table public.pesan_atasan;
exception when others then null;
end $$;

-- Kirim pesan ke atasan lain
create or replace function public.kirim_pesan(p_ke uuid, p_isi text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_id uuid;
begin
  if public.my_role() not in ('tl', 'trainer', 'pic') then raise exception 'Akses ditolak'; end if;
  if not exists (select 1 from public.profiles where id = p_ke and aktif and role in ('tl', 'trainer', 'pic')) then
    raise exception 'Penerima tidak ditemukan';
  end if;
  if p_ke = v_me then raise exception 'Tidak bisa mengirim ke diri sendiri'; end if;
  if coalesce(trim(p_isi), '') = '' then raise exception 'Pesan kosong'; end if;
  insert into public.pesan_atasan (dari, ke, isi) values (v_me, p_ke, left(trim(p_isi), 2000)) returning id into v_id;
  perform public.push_ke_kirim_notif(jsonb_build_object('pesan_id', v_id));
  return v_id;
end $$;

-- Tandai semua pesan dari seseorang sudah dibaca
create or replace function public.baca_pesan(p_dari uuid) returns void
language sql security definer set search_path = public as $$
  update public.pesan_atasan set dibaca_pada = now()
   where ke = public.my_profile_id() and dari = p_dari and dibaca_pada is null
$$;

-- Daftar kontak atasan + pesan terakhir + jumlah belum dibaca
create or replace function public.kontak_atasan() returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select public.my_profile_id() as id)
  select coalesce(jsonb_agg(x order by x->>'terakhir_pada' desc nulls last, x->>'nama'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id, 'nama', p.nama, 'role', p.role,
        'area', (select nama from public.areas where id = p.area_id),
        'terakhir', (select isi from public.pesan_atasan m
                      where (m.dari = p.id and m.ke = (select id from me)) or (m.ke = p.id and m.dari = (select id from me))
                      order by m.created_at desc limit 1),
        'terakhir_pada', (select max(created_at) from public.pesan_atasan m
                           where (m.dari = p.id and m.ke = (select id from me)) or (m.ke = p.id and m.dari = (select id from me))),
        'belum_dibaca', (select count(*) from public.pesan_atasan m
                          where m.dari = p.id and m.ke = (select id from me) and m.dibaca_pada is null)
      ) as x
        from public.profiles p
       where p.aktif and p.role in ('tl', 'trainer', 'pic') and p.id <> (select id from me)
         and public.my_role() in ('tl', 'trainer', 'pic')
    ) t
$$;

create or replace function public.pesan_belum_dibaca() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.pesan_atasan where ke = public.my_profile_id() and dibaca_pada is null
$$;

select 'Tahap 2i siap' as status;
