-- =====================================================================
-- Daily Report NKA - Notifikasi aktivitas ke TL, Trainer, dan PIC NKA
-- Setiap aktivitas di toko (penjualan, stok, MS Allbrand, display, NOSELL,
-- kirim laporan, istirahat mulai/kembali/telat) dicatat di tabel "aktivitas",
-- tampil di menu Aktivitas aplikasi atasan, dan dikirim sebagai push (Firebase)
-- ke HP TL & Trainer area toko itu serta PIC NKA, walau aplikasi tidak dibuka.
--
-- Jalankan SETELAH tahap1b.sql. Butuh extension pg_net dan pg_cron
-- (Database -> Extensions). Aman dijalankan ulang.
-- =====================================================================
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- 1. TABEL AKTIVITAS
-- ---------------------------------------------------------------------
create table if not exists public.aktivitas (
  id uuid primary key default gen_random_uuid(),
  store_id int not null references public.stores(id),
  oleh uuid references public.profiles(id),          -- yang melakukan (PC / TL)
  jenis text not null check (jenis in (
    'penjualan_hp', 'penjualan_iot', 'hapus_penjualan', 'nosell', 'stok', 'ms_allbrand', 'display',
    'laporan', 'istirahat_mulai', 'istirahat_selesai', 'istirahat_telat')),
  judul text not null,
  isi text not null,
  tanggal date not null default public.today_wib(),
  ref_id uuid,
  push_pada timestamptz,
  push_jumlah int,
  created_at timestamptz not null default now()
);
create index if not exists aktivitas_created_idx on public.aktivitas(created_at desc);
create index if not exists aktivitas_store_idx on public.aktivitas(store_id, created_at desc);

alter table public.aktivitas enable row level security;
drop policy if exists aktivitas_select on public.aktivitas;
create policy aktivitas_select on public.aktivitas for select to authenticated
  using (public.my_role() in ('tl', 'trainer', 'pic') and public.can_view_store(store_id));

-- Agar daftar Aktivitas langsung bertambah tanpa refresh
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'aktivitas') then
    alter publication supabase_realtime add table public.aktivitas;
  end if;
end $$;

-- Status "sudah dibaca" per orang
alter table public.profiles add column if not exists inbox_dibaca_pada timestamptz;

create or replace function public.set_inbox_dibaca() returns void
language sql security definer set search_path = public as $$
  update public.profiles set inbox_dibaca_pada = now() where auth_uid = auth.uid()
$$;

create or replace function public.my_inbox_unread() returns int
language sql stable security invoker set search_path = public as $$
  select count(*)::int from public.aktivitas a
   where a.created_at > coalesce((select inbox_dibaca_pada from public.profiles where auth_uid = auth.uid()), '-infinity'::timestamptz)
     and a.oleh is distinct from public.my_profile_id()
$$;

-- ---------------------------------------------------------------------
-- 2. FUNGSI BANTU
-- ---------------------------------------------------------------------
create or replace function public.rp(v bigint) returns text
language sql immutable as $$ select 'Rp' || replace(to_char(coalesce(v, 0), 'FM999,999,999,999'), ',', '.') $$;

create or replace function public.jam_wib(ts timestamptz) returns text
language sql immutable as $$ select to_char(ts at time zone 'Asia/Jakarta', 'HH24.MI') $$;

-- "Utin Amelia Putri Dewi · Erafone Pangkalanbun" atau "Alwisiuts Jati Kurniawan (TL) · Erafone Rajawali"
create or replace function public.label_aktor(p_profile uuid, p_store int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select p.nama || case when p.role = 'pc' then '' when p.role = 'tl' then ' (TL)'
                                         when p.role = 'trainer' then ' (Trainer)' else ' (PIC)' end
                     from public.profiles p where p.id = p_profile), 'Sistem')
         || ' · ' || coalesce((select nama from public.stores where id = p_store), '-')
$$;

create or replace function public.catat_aktivitas(p_store int, p_oleh uuid, p_jenis text, p_judul text,
                                                  p_isi text, p_tanggal date, p_ref uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.aktivitas (store_id, oleh, jenis, judul, isi, tanggal, ref_id)
  values (p_store, p_oleh, p_jenis, p_judul, p_isi, coalesce(p_tanggal, public.today_wib()), p_ref)
$$;

-- ---------------------------------------------------------------------
-- 3. TRIGGER AKTIVITAS
-- ---------------------------------------------------------------------
-- Penjualan baru / dihapus
create or replace function public.ev_sale() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.catat_aktivitas(new.store_id, new.diinput_oleh,
      case when new.tipe = 'HP' then 'penjualan_hp' else 'penjualan_iot' end,
      case when new.tipe = 'HP' then 'Penjualan HP' else 'Penjualan IoT' end,
      public.label_aktor(new.diinput_oleh, new.store_id) || ': ' || new.nama_produk || ' x' || new.qty
        || ' · ' || public.rp(new.qty * new.harga)
        || coalesce(' · ' || new.metode || coalesce(' ' || new.cara_bayar, ''), '')
        || case when new.tanggal <> public.today_wib() then ' · untuk tgl ' || to_char(new.tanggal, 'DD/MM') else '' end,
      new.tanggal, new.id);
  else
    perform public.catat_aktivitas(old.store_id, public.my_profile_id(), 'hapus_penjualan', 'Penjualan dihapus',
      public.label_aktor(public.my_profile_id(), old.store_id) || ' menghapus ' || old.nama_produk || ' x' || old.qty
        || ' (' || to_char(old.tanggal, 'DD/MM') || ')',
      old.tanggal, old.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_ev_sale on public.sales;
create trigger trg_ev_sale after insert or delete on public.sales for each row execute function public.ev_sale();

-- Update stok: satu pesan per simpan (bukan per produk)
create or replace function public.ev_stok() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.aktivitas where store_id = new.store_id and jenis = 'stok' and created_at = now()) then
    return null;
  end if;
  perform public.catat_aktivitas(new.store_id, new.diinput_oleh, 'stok',
    case when tg_op = 'INSERT' then 'Update stok' else 'Koreksi stok' end,
    public.label_aktor(new.diinput_oleh, new.store_id)
      || case when tg_op = 'INSERT' then ' update stok' else ' koreksi stok' end
      || ' pukul ' || public.jam_wib(now()) || ' WIB',
    new.tanggal, null);
  return null;
end $$;
drop trigger if exists trg_ev_stok on public.stock_daily;
create trigger trg_ev_stok after insert or update on public.stock_daily for each row execute function public.ev_stok();

-- Tidak ada penjualan (NOSELL)
create or replace function public.ev_nosell() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.modul = 'penjualan' then
    perform public.catat_aktivitas(new.store_id, new.oleh, 'nosell', 'NOSELL',
      public.label_aktor(new.oleh, new.store_id) || ' melaporkan tidak ada penjualan ' || to_char(new.tanggal, 'DD/MM'),
      new.tanggal, null);
  end if;
  return null;
end $$;
drop trigger if exists trg_ev_nosell on public.checkins;
create trigger trg_ev_nosell after insert on public.checkins for each row execute function public.ev_nosell();

-- Cek display
create or replace function public.ev_display() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.catat_aktivitas(new.store_id, new.diinput_oleh, 'display',
    case when tg_op = 'INSERT' then 'Cek display' else 'Update cek display' end,
    public.label_aktor(new.diinput_oleh, new.store_id) || ' mengirim cek display pukul ' || public.jam_wib(now()) || ' WIB'
      || coalesce(' · ' || new.catatan, ''),
    new.tanggal, new.id);
  return null;
end $$;
drop trigger if exists trg_ev_display on public.display_reports;
create trigger trg_ev_display after insert or update on public.display_reports for each row execute function public.ev_display();

-- Laporan malam dikirim
create or replace function public.ev_laporan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.catat_aktivitas(new.store_id, new.dikirim_oleh, 'laporan', 'Laporan dikirim',
    public.label_aktor(new.dikirim_oleh, new.store_id) || ' mengirim laporan ' || to_char(new.tanggal, 'DD/MM')
      || ' pukul ' || public.jam_wib(new.dikirim_pada) || ' WIB'
      || case when new.tanggal < public.to_wib(new.dikirim_pada)
                or (new.dikirim_pada at time zone 'Asia/Jakarta')::time >= time '22:00' then ' (TERLAMBAT)' else '' end
      || coalesce(' · ' || new.catatan, ''),
    new.tanggal, null);
  return null;
end $$;
drop trigger if exists trg_ev_laporan on public.daily_reports;
create trigger trg_ev_laporan after insert on public.daily_reports for each row execute function public.ev_laporan();

-- Istirahat mulai / kembali (beserta keterlambatan)
create or replace function public.ev_break() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_dur text := case when new.durasi_menit = 60 then '1 jam' else '2 jam' end;
begin
  if tg_op = 'INSERT' then
    perform public.catat_aktivitas(new.store_id, new.pc_id, 'istirahat_mulai', 'Mulai istirahat ' || v_dur,
      public.label_aktor(new.pc_id, new.store_id) || ' mulai istirahat ' || v_dur || ' pukul ' || public.jam_wib(new.mulai)
        || ' WIB · batas kembali ' || public.jam_wib(new.mulai + make_interval(mins => new.durasi_menit)) || ' WIB'
        || coalesce(' · selfie ' || new.jarak_mulai_m || ' m dari toko', ''),
      new.tanggal, new.id);
  elsif new.selesai is not null and old.selesai is null then
    perform public.catat_aktivitas(new.store_id, new.pc_id, 'istirahat_selesai',
      case when coalesce(new.terlambat_menit, 0) > 0 then 'Kembali ke toko (TERLAMBAT ' || new.terlambat_menit || ' menit)'
           else 'Kembali ke toko' end,
      public.label_aktor(new.pc_id, new.store_id) || ' kembali ke toko pukul ' || public.jam_wib(new.selesai) || ' WIB · istirahat '
        || round(extract(epoch from (new.selesai - new.mulai)) / 60) || ' menit dari ' || v_dur
        || case when coalesce(new.terlambat_menit, 0) > 0 then ' · TERLAMBAT ' || new.terlambat_menit || ' menit' else '' end,
      new.tanggal, new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_ev_break on public.breaks;
create trigger trg_ev_break after insert or update on public.breaks for each row execute function public.ev_break();

-- MS Allbrand: dicatat di dalam RPC simpan (sekali per simpan, berisi ringkasan per brand)
create or replace function public.simpan_ms_allbrand(p_store int, p_tanggal date, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_ringkas text;
  v_total int;
begin
  if not public.can_write_daily(p_store, p_tanggal) then
    raise exception 'Tidak diizinkan. PC hanya bisa input hari ini sebelum 22.00 WIB.';
  end if;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  insert into public.competitor_sales_detail (store_id, tanggal, brand_id, segmen, tipe, unit, diinput_oleh)
  select p_store, p_tanggal, (d->>'brand_id')::int, d->>'segmen', trim(d->>'tipe'), (d->>'unit')::int, v_me
    from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) d
   where coalesce((d->>'unit')::int, 0) > 0;
  insert into public.competitor_sales (store_id, tanggal, brand_id, unit, diinput_oleh, updated_at)
  select p_store, p_tanggal, b.id,
         coalesce((select sum(x.unit) from public.competitor_sales_detail x
                    where x.store_id = p_store and x.tanggal = p_tanggal and x.brand_id = b.id), 0),
         v_me, now()
    from public.competitor_brands b
   where b.aktif
  on conflict (store_id, tanggal, brand_id) do update
     set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();

  select string_agg(b.nama || ' ' || c.unit, ', ' order by c.unit desc, b.urutan), coalesce(sum(c.unit), 0)
    into v_ringkas, v_total
    from public.competitor_sales c join public.competitor_brands b on b.id = c.brand_id
   where c.store_id = p_store and c.tanggal = p_tanggal and c.unit > 0;
  perform public.catat_aktivitas(p_store, v_me, 'ms_allbrand', 'MS Allbrand',
    public.label_aktor(v_me, p_store) || ': brand lain ' || v_total || ' unit'
      || coalesce(' (' || v_ringkas || ')', ' (tidak ada penjualan brand lain)'),
    p_tanggal, null);
end $$;

-- ---------------------------------------------------------------------
-- 4. PENGINGAT ISTIRAHAT TELAT (dicek setiap 5 menit oleh pg_cron)
-- ---------------------------------------------------------------------
create or replace function public.cek_istirahat_telat() returns int
language plpgsql security definer set search_path = public as $$
declare b record; n int := 0;
begin
  for b in
    select * from public.breaks
     where selesai is null and peringatan_pada is null
       and mulai < now() - make_interval(mins => durasi_menit)
  loop
    perform public.catat_aktivitas(b.store_id, b.pc_id, 'istirahat_telat', 'Belum kembali dari istirahat',
      public.label_aktor(b.pc_id, b.store_id) || ' mulai istirahat ' || case when b.durasi_menit = 60 then '1 jam' else '2 jam' end
        || ' pukul ' || public.jam_wib(b.mulai) || ' WIB dan BELUM KEMBALI ke toko (lewat '
        || floor(extract(epoch from (now() - b.mulai)) / 60)::int - b.durasi_menit || ' menit)',
      b.tanggal, b.id);
    update public.breaks set peringatan_pada = now() where id = b.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.cek_istirahat_telat() from public, anon, authenticated;

select cron.unschedule('nka-cek-istirahat') where exists (select 1 from cron.job where jobname = 'nka-cek-istirahat');
select cron.schedule('nka-cek-istirahat', '*/5 * * * *', $$ select public.cek_istirahat_telat(); $$);

-- ---------------------------------------------------------------------
-- 5. PUSH: setiap aktivitas baru dikirim ke edge function "kirim-notif"
--    (Firebase Cloud Messaging) -> HP TL & Trainer area toko + PIC NKA.
--    Kegagalan push tidak membatalkan input PC.
-- ---------------------------------------------------------------------
create or replace function public.ev_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform net.http_post(
      url := 'https://stsuljrjjnjeqixetcqf.supabase.co/functions/v1/kirim-notif',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('event_id', new.id)
    );
  exception when others then
    null;
  end;
  return null;
end $$;
drop trigger if exists trg_ev_push on public.aktivitas;
create trigger trg_ev_push after insert on public.aktivitas for each row execute function public.ev_push();

select 'Notifikasi aktivitas siap' as status;
