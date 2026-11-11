-- =====================================================================
-- Daily Report NKA - Pilihan istirahat menjadi 1 jam atau 3 jam
-- Jalankan SETELAH tahap1j.sql. Aman dijalankan ulang.
-- Data istirahat lama (2 jam) tetap sah dan tetap tampil sebagai "2 jam".
-- =====================================================================

-- 1. Kolom durasi menerima 60 dan 180 menit (120 tetap diizinkan untuk data lama)
alter table public.breaks drop constraint if exists breaks_durasi_menit_check;
alter table public.breaks add constraint breaks_durasi_menit_check check (durasi_menit in (60, 120, 180));

-- 2. Fungsi server: pilihan baru + label durasi mengikuti angka menitnya
do $$
declare d text; d2 text;
begin
  -- Mulai istirahat: hanya 1 jam atau 3 jam
  d := pg_get_functiondef('public.mulai_istirahat(integer,text,double precision,double precision)'::regprocedure);
  d2 := replace(replace(d, 'p_durasi not in (60, 120)', 'p_durasi not in (60, 180)'),
                'Durasi istirahat hanya 1 jam atau 2 jam', 'Durasi istirahat hanya 1 jam atau 3 jam');
  if d2 <> d then execute d2; end if;

  -- Notifikasi mulai / kembali istirahat
  d := pg_get_functiondef('public.ev_break()'::regprocedure);
  d2 := replace(d, 'case when new.durasi_menit = 60 then ''1 jam'' else ''2 jam'' end',
                   '(new.durasi_menit / 60)::text || '' jam''');
  if d2 <> d then execute d2; end if;

  -- Notifikasi belum kembali dari istirahat
  d := pg_get_functiondef('public.cek_istirahat_telat()'::regprocedure);
  d2 := replace(d, 'case when b.durasi_menit = 60 then ''1 jam'' else ''2 jam'' end',
                   '(b.durasi_menit / 60)::text || '' jam''');
  if d2 <> d then execute d2; end if;
end $$;

select position('(60, 180)' in pg_get_functiondef('public.mulai_istirahat(integer,text,double precision,double precision)'::regprocedure)) > 0
         as mulai_istirahat_1_3_jam,
       position('''2 jam''' in pg_get_functiondef('public.ev_break()'::regprocedure)) = 0 as notifikasi_label_baru;
