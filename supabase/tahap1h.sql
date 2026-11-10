-- =====================================================================
-- Daily Report NKA - Batas laporan PC pukul 22.30 WIB
-- - PC bisa input data harian, mulai istirahat, dan kirim laporan sampai 22.30 WIB
-- - Pukul 22.30 WIB itu juga, PC yang belum kirim laporan langsung dikirim notifikasi
--   "PC tidak kirim laporan" ke TL & Trainer area + PIC NKA
-- Jalankan SETELAH tahap1g.sql. Aman dijalankan ulang.
-- =====================================================================

-- 1. Ganti batas 22.00 -> 22.30 di semua fungsi server yang memakainya
do $$
declare
  f text;
  d text;
  d2 text;
begin
  foreach f in array array[
    'public.can_write_daily(integer,date)',
    'public.mulai_istirahat(integer,text,double precision,double precision)',
    'public.kirim_laporan(integer,date,text)',
    'public.simpan_ms_allbrand(integer,date,jsonb)',
    'public.ev_laporan()'
  ] loop
    d := pg_get_functiondef(f::regprocedure);
    d2 := replace(replace(d, 'time ''22:00''', 'time ''22:30'''), '22.00 WIB', '22.30 WIB');
    if d2 <> d then execute d2; end if;
  end loop;
end $$;

-- 2. Cek PC tidak kirim laporan tepat pukul 22.30 WIB (= 15.30 UTC), menggantikan jadwal 23.00
select cron.unschedule('nka-tidak-lapor') where exists (select 1 from cron.job where jobname = 'nka-tidak-lapor');
select cron.schedule('nka-tidak-lapor', '30 15 * * *', $$ select public.cek_tidak_lapor(); $$);

-- Cek hasil: semua fungsi di atas harus sudah memakai 22:30
select f as fungsi, position('22:30' in pg_get_functiondef(f::regprocedure)) > 0 as sudah_22_30
  from unnest(array[
    'public.can_write_daily(integer,date)',
    'public.mulai_istirahat(integer,text,double precision,double precision)',
    'public.ev_laporan()'
  ]) f;
