-- =====================================================================
-- Daily Report NKA - Tahap 2n: foto PC hanya disimpan 4 hari
--   Semua foto yang diupload PC (display, selfie istirahat, activity/sosmed, cek limit) dihapus
--   otomatis setelah 4 hari (pembersihan harian 02.00 WIB). Jika storage masih >= 80%,
--   foto yang lebih baru ikut dihapus, kecuali foto 1 hari terakhir.
--   Foto profil tidak dihapus.
-- Setelah menjalankan file ini, tempel ulang kode supabase/functions/kirim-notif/index.ts
-- ke edge function kirim-notif lalu Deploy.
-- Jalankan SETELAH tahap2m.sql. Aman dijalankan ulang.
-- =====================================================================

insert into public.pengaturan (kunci, nilai) values ('umur_foto_hari', '4')
on conflict (kunci) do update set nilai = '4';
insert into public.pengaturan (kunci, nilai) values ('simpan_minimal_hari', '1')
on conflict (kunci) do update set nilai = '1';

-- Langsung bersihkan sekarang (foto > 4 hari dihapus)
select public.jalankan_bersihkan('jadwal');

select kunci, nilai from public.pengaturan where kunci in ('umur_foto_hari', 'simpan_minimal_hari');
