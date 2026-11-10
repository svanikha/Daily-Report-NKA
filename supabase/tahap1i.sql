-- =====================================================================
-- Daily Report NKA - Revisi dashboard & akun PC
-- 1. Nama TL Palangkaraya: Alwisius Jati Kurniawan
-- 2. Rekap toko menyertakan nama Trainer (untuk gambar laporan)
-- 3. Kalender penjualan menandai offday & NOSELL
-- 4. Kontribusi penjualan HP & IoT: Cash / Kredit / per leasing
-- 5. Kelola akun PC: PIC (semua) dan TL & Trainer (areanya) bisa tambah, ubah nama,
--    pindah toko, hapus, reset password
-- Jalankan SETELAH tahap1h.sql. Aman dijalankan ulang.
-- =====================================================================

-- 1. Perbaikan nama (email login tidak berubah)
update public.profiles set nama = 'Alwisius Jati Kurniawan'
 where email = 'alwisiuts@dailyreportnka.app' and nama <> 'Alwisius Jati Kurniawan';

-- 2. Nama Trainer di rekap toko (disisipkan setelah nama TL)
do $$
declare d text; d2 text;
begin
  d := pg_get_functiondef('public.rekap_toko(integer,date)'::regprocedure);
  if position('''trainer'',' in d) = 0 then
    d2 := replace(d, '''libur'', (select status',
      '''trainer'', (select string_agg(nama, '', '' order by nama) from public.profiles where role = ''trainer'' and aktif and area_id = v_area),' || chr(10)
      || '    ''libur'', (select status');
    if d2 = d then raise exception 'rekap_toko: posisi sisipan tidak ditemukan'; end if;
    execute d2;
  end if;
end $$;

-- 3. Kalender penjualan: per hari unit & value HP, IoT, kompetitor, laporan,
--    serta tanda offday PC dan NOSELL (hanya bermakna jika satu toko dipilih)
create or replace function public.kalender_penjualan(p_bulan date, p_store int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with toko as (
    select id from public.stores
     where aktif and public.can_view_store(id) and (p_store is null or id = p_store)
  ), pc as (
    select p.id from public.profiles p where p_store is not null and p.store_id = p_store and p.role = 'pc' and p.aktif
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
                       and d.store_id in (select id from toko)),
           'off', exists (select 1 from public.pc_day_status d where d.tanggal = h.tanggal and d.pc_id in (select id from pc)),
           'nihil', exists (select 1 from public.checkins c where c.tanggal = h.tanggal and c.modul = 'penjualan'
                              and c.store_id in (select id from toko))
         ) order by h.tanggal), '[]'::jsonb)
    from hari h
$$;

-- 4. Kontribusi pembayaran: HP & IoT per metode (Cash/Kredit) dan cara bayar (leasing)
create or replace function public.kontribusi_bayar(p_dari date, p_sampai date, p_store int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'metode', metode, 'cara_bayar', cara_bayar, 'unit', unit, 'value', value)
         order by tipe, metode, value desc), '[]'::jsonb)
    from (
      select s.tipe, coalesce(s.metode, '-') as metode, coalesce(s.cara_bayar, '-') as cara_bayar,
             sum(s.qty) as unit, sum(s.subtotal) as value
        from public.sales s
        join public.stores st on st.id = s.store_id
       where s.tanggal between p_dari and p_sampai
         and st.aktif and public.can_view_store(s.store_id)
         and (p_store is null or s.store_id = p_store)
       group by 1, 2, 3
    ) x
$$;

-- 5. Kelola akun PC
create or replace function public.can_manage_pc(p_store int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_pic()
      or (public.my_role() in ('tl', 'trainer') and public.store_area(p_store) = public.my_area_id())
$$;

-- Tambah PC baru (p_id null) atau ubah nama / pindah toko PC yang ada.
create or replace function public.simpan_pc(p_id uuid, p_nama text, p_store int) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v public.profiles;
  v_id uuid;
begin
  if coalesce(trim(p_nama), '') = '' then raise exception 'Nama PC wajib diisi'; end if;
  if not exists (select 1 from public.stores where id = p_store and aktif) then raise exception 'Toko tidak ditemukan'; end if;
  if not public.can_manage_pc(p_store) then raise exception 'Toko ini di luar area kamu'; end if;
  if p_id is null then
    insert into public.profiles (nama, role, store_id, email)
    values (trim(p_nama), 'pc', p_store,
            'pc' || to_char(now(), 'YYMMDDHH24MISS') || substr(md5(random()::text), 1, 4) || '@dailyreportnka.app')
    returning id into v_id;
    return v_id;
  end if;
  select * into v from public.profiles where id = p_id;
  if v.id is null or v.role <> 'pc' then raise exception 'Akun PC tidak ditemukan'; end if;
  if not public.can_manage_pc(v.store_id) then raise exception 'PC ini di luar area kamu'; end if;
  update public.profiles set nama = trim(p_nama), store_id = p_store, aktif = true where id = p_id;
  return p_id;
end $$;

-- Hapus PC: akun dinonaktifkan dan login dihapus. Riwayat penjualan & laporan tetap tersimpan.
create or replace function public.hapus_pc(p_id uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v public.profiles;
begin
  select * into v from public.profiles where id = p_id;
  if v.id is null or v.role <> 'pc' then raise exception 'Akun PC tidak ditemukan'; end if;
  if not public.can_manage_pc(v.store_id) then raise exception 'PC ini di luar area kamu'; end if;
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set aktif = false, auth_uid = null, fcm_token = null where id = p_id;
end $$;

-- Reset password: PIC untuk semua akun selain PIC; TL & Trainer untuk PC di areanya.
create or replace function public.reset_password(p_profile uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v public.profiles;
begin
  select * into v from public.profiles where id = p_profile;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.role = 'pic' then raise exception 'Password PIC NKA diatur di Supabase'; end if;
  if not (public.is_pic() or (v.role = 'pc' and public.can_manage_pc(v.store_id))) then
    raise exception 'Akses ditolak';
  end if;
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  update public.profiles set auth_uid = null where id = p_profile;
end $$;

select 'Revisi dashboard & akun PC siap' as status,
       position('''trainer'',' in pg_get_functiondef('public.rekap_toko(integer,date)'::regprocedure)) > 0 as rekap_ada_trainer;
