-- =====================================================================
-- Daily Report NKA - Tahap 2k
--   1. Daftar kontak pesan atasan membawa status online (lampu hijau / merah).
--   2. Manajer Trainer & PIC NKA (role pic) bisa menghapus riwayat chat antar atasan:
--      semua sekaligus, atau satu percakapan.
-- Jalankan SETELAH tahap2j.sql. Aman dijalankan ulang.
-- =====================================================================

create or replace function public.kontak_atasan() returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select public.my_profile_id() as id)
  select coalesce(jsonb_agg(x order by x->>'terakhir_pada' desc nulls last, x->>'nama'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id, 'nama', p.nama, 'role', p.role, 'jabatan', p.jabatan, 'foto_url', p.foto_url,
        'auth_uid', p.auth_uid, 'last_seen', p.last_seen, 'last_login', p.last_login, 'logged_in', p.logged_in,
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

-- Status online satu atasan (untuk judul halaman chat)
create or replace function public.status_atasan(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('auth_uid', auth_uid, 'last_seen', last_seen, 'last_login', last_login, 'logged_in', logged_in)
    from public.profiles
   where id = p_id and role in ('tl', 'trainer', 'pic') and public.my_role() in ('tl', 'trainer', 'pic')
$$;

-- Hapus SEMUA riwayat chat antar atasan (semua orang). Hanya Manajer Trainer / PIC NKA.
create or replace function public.hapus_semua_pesan() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_pic() then raise exception 'Hanya Manajer Trainer / PIC NKA yang bisa menghapus riwayat chat'; end if;
  delete from public.pesan_atasan;
  get diagnostics n = row_count;
  return n;
end $$;

-- Hapus satu percakapan antara akun ini dan p_lawan. Hanya Manajer Trainer / PIC NKA.
create or replace function public.hapus_percakapan(p_lawan uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  n int;
begin
  if not public.is_pic() then raise exception 'Hanya Manajer Trainer / PIC NKA yang bisa menghapus riwayat chat'; end if;
  delete from public.pesan_atasan where (dari = v_me and ke = p_lawan) or (dari = p_lawan and ke = v_me);
  get diagnostics n = row_count;
  return n;
end $$;

select 'Tahap 2k siap' as status;
