-- =====================================================================
-- Daily Report NKA - Tahap 2j
--   1. Akun baru: Akhmad Saifuddin, jabatan Manajer Trainer, akses setara PIC NKA
--      (role 'pic' + kolom jabatan). Membuat password sendiri saat login pertama.
--   2. Foto profil untuk semua akun (bucket publik "profil").
--   3. Kontribusi kategori user (Walk-in / Databased / Online) untuk dashboard atasan.
--   (Balasan bebas PC ke pengingat memakai fungsi respon_pengingat yang sudah ada.)
-- Jalankan SETELAH tahap2i.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. JABATAN & AKUN MANAJER TRAINER
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists jabatan text;
alter table public.profiles add column if not exists foto_url text;

insert into public.profiles (nama, role, email, jabatan)
values ('Akhmad Saifuddin', 'pic', 'akhmad.saifuddin@dailyreportnka.app', 'Manajer Trainer')
on conflict (email) do update set nama = excluded.nama, role = 'pic', jabatan = 'Manajer Trainer', aktif = true;

-- Label pelaku di notifikasi memakai jabatan bila ada
create or replace function public.label_aktor(p_profile uuid, p_store int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select p.nama || case when p.role = 'pc' then ''
                                         when p.jabatan is not null then ' (' || p.jabatan || ')'
                                         when p.role = 'tl' then ' (TL)'
                                         when p.role = 'trainer' then ' (Trainer)' else ' (PIC)' end
                     from public.profiles p where p.id = p_profile), 'Sistem')
         || ' · ' || coalesce((select nama from public.stores where id = p_store), '-')
$$;

create or replace function public.my_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email,
           'jabatan', p.jabatan, 'foto_url', p.foto_url,
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

create or replace function public.list_login_profiles() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'nama', p.nama, 'role', p.role, 'email', p.email, 'jabatan', p.jabatan,
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

-- Reset password: PIC untuk semua akun kecuali PIC NKA utama (yang diatur di Supabase).
-- Akun berjabatan (Manajer Trainer) bisa direset oleh PIC.
create or replace function public.reset_password(p_profile uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v public.profiles;
begin
  select * into v from public.profiles where id = p_profile;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.role = 'pic' and v.jabatan is null then raise exception 'Password PIC NKA diatur di Supabase'; end if;
  if v.id = public.my_profile_id() then raise exception 'Gunakan menu Ganti password untuk akun sendiri'; end if;
  if not (public.is_pic() or (v.role = 'pc' and public.can_manage_pc(v.store_id))) then
    raise exception 'Akses ditolak';
  end if;
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set auth_uid = null where id = p_profile;
end $$;

-- Kontak pesan: sertakan jabatan & foto
create or replace function public.kontak_atasan() returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select public.my_profile_id() as id)
  select coalesce(jsonb_agg(x order by x->>'terakhir_pada' desc nulls last, x->>'nama'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id, 'nama', p.nama, 'role', p.role, 'jabatan', p.jabatan, 'foto_url', p.foto_url,
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

-- ---------------------------------------------------------------------
-- 2. FOTO PROFIL
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('profil', 'profil', true, 2097152)
on conflict (id) do update set public = true, file_size_limit = 2097152;

-- Path: <profile_id>/foto.jpg — setiap akun hanya boleh menulis foldernya sendiri
drop policy if exists profil_insert on storage.objects;
create policy profil_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'profil' and (storage.foldername(name))[1] = public.my_profile_id()::text);
drop policy if exists profil_update on storage.objects;
create policy profil_update on storage.objects for update to authenticated
  using (bucket_id = 'profil' and (storage.foldername(name))[1] = public.my_profile_id()::text);
drop policy if exists profil_select on storage.objects;
create policy profil_select on storage.objects for select to authenticated
  using (bucket_id = 'profil');
drop policy if exists profil_delete on storage.objects;
create policy profil_delete on storage.objects for delete to authenticated
  using (bucket_id = 'profil' and (storage.foldername(name))[1] = public.my_profile_id()::text);

create or replace function public.set_foto_profil(p_url text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set foto_url = nullif(trim(p_url), '') where auth_uid = auth.uid()
$$;

-- ---------------------------------------------------------------------
-- 3. KONTRIBUSI KATEGORI USER (tgl 1 s.d. p_tanggal), p_store null = semua toko di cakupan
-- ---------------------------------------------------------------------
create or replace function public.kontribusi_kategori(p_store int, p_tanggal date) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('tipe', tipe, 'kategori', kategori, 'unit', unit, 'value', value,
                                               'unit_hari', unit_hari)), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.kategori_user, 'Belum diisi') as kategori,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             coalesce(sum(x.qty) filter (where x.tanggal = p_tanggal), 0) as unit_hari
        from public.sales x
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select id from public.stores
                             where aktif and public.can_view_store(id) and (p_store is null or id = p_store))
       group by 1, 2
    ) t
$$;

select 'Tahap 2j siap' as status,
       (select count(*) from public.profiles where jabatan = 'Manajer Trainer') as akun_manajer;
