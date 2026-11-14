-- =====================================================================
-- Daily Report NKA - Tahap 2l: pembersihan penyimpanan otomatis
--   Setiap hari pukul 02.00 WIB (dan lewat tombol di aplikasi PIC):
--   1. Foto bukti (bucket "bukti": display, selfie istirahat, sosmed, cek limit) yang lebih tua
--      dari 30 hari dihapus.
--   2. Jika penyimpanan masih >= 80% kuota, foto tertua ikut dihapus sampai di bawah 70%
--      (foto 7 hari terakhir selalu disimpan).
--   3. APK lama dihapus, hanya 5 APK terbaru per saluran (uji / rilis) yang disimpan.
--   Foto profil (bucket "profil") tidak pernah dihapus.
--   Penghapusan file dikerjakan edge function "kirim-notif" (body {"bersihkan": ...}).
-- Setelah menjalankan file ini, tempel ulang kode supabase/functions/kirim-notif/index.ts
-- ke edge function kirim-notif lalu Deploy.
-- Jalankan SETELAH tahap2k.sql. Aman dijalankan ulang.
-- =====================================================================

-- Pengaturan sederhana (kunci rahasia pembersihan, kuota, umur foto)
create table if not exists public.pengaturan (
  kunci text primary key,
  nilai text not null
);
alter table public.pengaturan enable row level security;   -- tanpa policy: hanya fungsi server yang membaca

insert into public.pengaturan (kunci, nilai) values
  ('bersih_token', encode(gen_random_bytes(24), 'hex')),
  ('kuota_storage_bytes', '1073741824'),     -- 1 GB (paket Free Supabase). Ubah jika paket naik.
  ('umur_foto_hari', '30'),
  ('batas_persen', '80'),
  ('target_persen', '70'),
  ('simpan_apk', '5')
on conflict (kunci) do nothing;

create table if not exists public.storage_bersih_log (
  id bigserial primary key,
  waktu timestamptz not null default now(),
  pemicu text,
  foto_dihapus int not null default 0,
  apk_dihapus int not null default 0,
  bytes_dibebaskan bigint not null default 0,
  ukuran_sebelum bigint,
  ukuran_sesudah bigint,
  catatan text
);
alter table public.storage_bersih_log enable row level security;
drop policy if exists storage_bersih_log_pic on public.storage_bersih_log;
create policy storage_bersih_log_pic on public.storage_bersih_log for select to authenticated using (public.is_pic());

-- Total ukuran file per bucket (byte)
create or replace function public.ukuran_storage() returns jsonb
language sql stable security definer set search_path = public, storage as $$
  select jsonb_build_object(
    'total', coalesce(sum((o.metadata->>'size')::bigint), 0),
    'per_bucket', coalesce((select jsonb_object_agg(b, s) from (
        select bucket_id as b, sum((metadata->>'size')::bigint) as s from storage.objects group by bucket_id) x), '{}'::jsonb))
  from storage.objects o
$$;
revoke execute on function public.ukuran_storage() from public, anon, authenticated;

-- Daftar file kandidat hapus (dipanggil edge function dengan service role)
create or replace function public.objek_storage(p_bucket text, p_sebelum timestamptz, p_prefix text default null,
                                                p_limit int default 1000)
returns table(name text, size bigint, created_at timestamptz)
language sql stable security definer set search_path = public, storage as $$
  select o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at
    from storage.objects o
   where o.bucket_id = p_bucket
     and o.created_at < p_sebelum
     and (p_prefix is null or o.name like p_prefix || '%')
   order by o.created_at
   limit p_limit
$$;
revoke execute on function public.objek_storage(text, timestamptz, text, int) from public, anon, authenticated;

-- APK yang boleh dihapus: selain p_simpan terbaru di setiap folder saluran
create or replace function public.apk_lama(p_simpan int default 5)
returns table(name text, size bigint)
language sql stable security definer set search_path = public, storage as $$
  select name, size from (
    select o.name, coalesce((o.metadata->>'size')::bigint, 0) as size,
           row_number() over (partition by split_part(o.name, '/', 1) order by o.created_at desc) as rn
      from storage.objects o
     where o.bucket_id = 'apk' and o.name like '%.apk'
  ) x where rn > p_simpan
$$;
revoke execute on function public.apk_lama(int) from public, anon, authenticated;

-- Info penyimpanan untuk kartu di aplikasi PIC
create or replace function public.info_storage() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u jsonb; k bigint;
begin
  if not public.is_pic() then raise exception 'Akses ditolak'; end if;
  u := public.ukuran_storage();
  k := (select nilai::bigint from public.pengaturan where kunci = 'kuota_storage_bytes');
  return jsonb_build_object(
    'total', u->'total', 'per_bucket', u->'per_bucket', 'kuota', k,
    'umur_hari', (select nilai::int from public.pengaturan where kunci = 'umur_foto_hari'),
    'batas_persen', (select nilai::int from public.pengaturan where kunci = 'batas_persen'),
    'log', (select coalesce(jsonb_agg(to_jsonb(l) order by l.waktu desc), '[]'::jsonb)
              from (select * from public.storage_bersih_log order by waktu desc limit 5) l));
end $$;

-- Panggil edge function untuk membersihkan (dari cron atau tombol PIC)
create or replace function public.jalankan_bersihkan(p_pemicu text default 'manual') returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pemicu = 'manual' and not public.is_pic() then raise exception 'Akses ditolak'; end if;
  perform net.http_post(
    url := 'https://stsuljrjjnjeqixetcqf.supabase.co/functions/v1/kirim-notif',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('bersihkan', (select nilai from public.pengaturan where kunci = 'bersih_token'),
                               'pemicu', p_pemicu),
    timeout_milliseconds := 120000
  );
end $$;

-- Jadwal harian 02.00 WIB = 19.00 UTC
select cron.unschedule('nka-bersih-storage') where exists (select 1 from cron.job where jobname = 'nka-bersih-storage');
select cron.schedule('nka-bersih-storage', '0 19 * * *', $$ select public.jalankan_bersihkan('jadwal'); $$);

select 'Pembersihan storage siap' as status,
       pg_size_pretty((public.ukuran_storage()->>'total')::bigint) as ukuran_sekarang;
