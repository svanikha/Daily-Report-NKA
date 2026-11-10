-- =====================================================================
-- Daily Report NKA - Notifikasi "PC tidak kirim laporan hari ini" (pukul 23.00 WIB)
-- Setiap hari pukul 23.00 WIB, PC yang bertugas (tidak offday/izin) dan belum mengirim
-- laporan malam dicatat di Aktivitas dan dikirim sebagai push ke TL & Trainer area + PIC NKA.
-- Jalankan SETELAH tahap1f.sql. Butuh pg_cron & pg_net (sudah aktif sejak tahap1c.sql).
-- Aman dijalankan ulang.
-- =====================================================================

alter table public.aktivitas drop constraint if exists aktivitas_jenis_check;
alter table public.aktivitas add constraint aktivitas_jenis_check check (jenis in (
  'penjualan_hp', 'penjualan_iot', 'hapus_penjualan', 'nosell', 'stok', 'ms_allbrand', 'display',
  'laporan', 'tidak_lapor', 'istirahat_mulai', 'istirahat_selesai', 'istirahat_telat', 'sosmed', 'leasing'));

-- Catat PC yang tidak mengirim laporan pada tanggal tertentu (default hari ini WIB).
-- Tidak dicatat dua kali untuk toko & tanggal yang sama.
create or replace function public.cek_tidak_lapor(p_tanggal date default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_tgl date := coalesce(p_tanggal, public.today_wib());
  r record;
  n int := 0;
begin
  for r in
    select s.id as store_id, s.nama as toko, p.id as pc_id, p.nama as pc,
           public.laporan_kurang(s.id, v_tgl) as kurang
      from public.stores s
      join lateral (select id, nama from public.profiles
                     where store_id = s.id and role = 'pc' and aktif order by created_at limit 1) p on true
     where s.aktif and s.punya_pc
       and not exists (select 1 from public.pc_day_status d where d.pc_id = p.id and d.tanggal = v_tgl)
       and not exists (select 1 from public.daily_reports x where x.store_id = s.id and x.tanggal = v_tgl)
       and not exists (select 1 from public.aktivitas a where a.store_id = s.id and a.tanggal = v_tgl and a.jenis = 'tidak_lapor')
  loop
    perform public.catat_aktivitas(r.store_id, r.pc_id, 'tidak_lapor', 'PC tidak kirim laporan',
      r.pc || ' · ' || r.toko || ' tidak mengirim laporan hari ini (' || to_char(v_tgl, 'DD/MM') || ')'
        || case when array_length(r.kurang, 1) > 0 then ' · belum: ' || array_to_string(r.kurang, ', ')
                else ' · data sudah lengkap tetapi tidak dikirim' end,
      v_tgl, null);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.cek_tidak_lapor(date) from public, anon, authenticated;

-- Jadwal: setiap hari pukul 23.00 WIB (= 16.00 UTC)
select cron.unschedule('nka-tidak-lapor') where exists (select 1 from cron.job where jobname = 'nka-tidak-lapor');
select cron.schedule('nka-tidak-lapor', '0 16 * * *', $$ select public.cek_tidak_lapor(); $$);

select 'Notifikasi PC tidak lapor (23.00 WIB) siap' as status;
