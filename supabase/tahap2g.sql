-- =====================================================================
-- Daily Report NKA - Tahap 2g: notifikasi HP tampil di layar kunci, spanduk, dan bilah notifikasi
--   - profiles.notif_channel: channel Android yang dipakai HP itu (aplikasi baru = "nka_penting",
--     prioritas tertinggi). HP dengan aplikasi lama tetap memakai "aktivitas".
--   - tes_notif(): kirim push percobaan ke HP sendiri (tombol "Tes notifikasi" di aplikasi).
-- Setelah menjalankan file ini, tempel ulang kode supabase/functions/kirim-notif/index.ts
-- ke edge function kirim-notif lalu Deploy.
-- Jalankan SETELAH tahap2f.sql. Aman dijalankan ulang.
-- =====================================================================

alter table public.profiles add column if not exists notif_channel text;
alter table public.profiles add column if not exists notif_cek_pada timestamptz;

-- Dipanggil aplikasi setiap login / buka aplikasi
create or replace function public.set_notif_channel(p_channel text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set notif_channel = nullif(trim(p_channel), ''), notif_cek_pada = now()
   where auth_uid = auth.uid()
$$;

-- Push percobaan ke HP sendiri
create or replace function public.tes_notif() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v public.profiles;
begin
  select * into v from public.profiles where auth_uid = auth.uid() and aktif;
  if v.id is null then raise exception 'Akun tidak ditemukan'; end if;
  if v.fcm_token is null then
    return jsonb_build_object('ok', false, 'pesan', 'HP ini belum terdaftar untuk push. Tutup lalu buka lagi aplikasinya.');
  end if;
  perform net.http_post(
    url := 'https://stsuljrjjnjeqixetcqf.supabase.co/functions/v1/kirim-notif',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('tes_profile', v.id)
  );
  return jsonb_build_object('ok', true, 'pesan', 'Push percobaan dikirim');
end $$;

select 'Tahap 2g siap' as status;
