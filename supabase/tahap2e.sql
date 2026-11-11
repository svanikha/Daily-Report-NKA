-- =====================================================================
-- Daily Report NKA - Tahap 2e
--   1. Cek display: PC wajib foto setiap kategori checklist (tanpa saklar).
--      TL / Trainer / PIC bisa menghapus isian satu kategori jika salah -> PC mengirim ulang.
--   2. Menu notifikasi (Aktivitas): hapus satu / hapus semua, per akun (tidak menghapus milik atasan lain).
--   3. Reset laporan PC satu tanggal oleh TL / Trainer / PIC: semua data harian toko jadi 0.
-- Jalankan SETELAH tahap2d.sql. Aman dijalankan ulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DISPLAY
-- ---------------------------------------------------------------------
-- Hapus isian satu kategori display (baris checklist + fotonya). PC diberi pengingat untuk kirim ulang.
create or replace function public.hapus_display_item(p_store int, p_tanggal date, p_item int) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_check uuid;
  v_nama text;
  v_pc uuid;
begin
  if public.my_role() not in ('tl', 'trainer', 'pic') or not public.can_view_store(p_store) then
    raise exception 'Akses ditolak';
  end if;
  select id into v_check from public.display_checks where store_id = p_store and tanggal = p_tanggal and item_id = p_item;
  select nama into v_nama from public.checklist_items where id = p_item;
  if v_check is not null then
    delete from public.photos where ref_tabel = 'display_checks' and ref_id = v_check;
    delete from public.display_checks where id = v_check;
  end if;
  perform public.catat_aktivitas(p_store, v_me, 'display', 'Display dihapus',
    public.label_aktor(v_me, p_store) || ' menghapus display "' || coalesce(v_nama, '-') || '" tgl '
      || to_char(p_tanggal, 'DD/MM') || ', PC perlu kirim ulang',
    p_tanggal, null);
  select id into v_pc from public.profiles where store_id = p_store and role = 'pc' and aktif order by created_at limit 1;
  if v_pc is not null and p_tanggal = public.today_wib() then
    insert into public.pengingat (store_id, pc_id, dari, modul, pesan)
    values (p_store, v_pc, v_me, array['display'],
            'Foto display "' || coalesce(v_nama, '-') || '" dihapus karena salah. Segera kirim ulang.');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. HAPUS NOTIFIKASI (per akun)
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists inbox_hapus_pada timestamptz;

create table if not exists public.aktivitas_disembunyikan (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  aktivitas_id uuid not null references public.aktivitas(id) on delete cascade,
  primary key (profile_id, aktivitas_id)
);
alter table public.aktivitas_disembunyikan enable row level security;
drop policy if exists aktivitas_disembunyikan_self on public.aktivitas_disembunyikan;
create policy aktivitas_disembunyikan_self on public.aktivitas_disembunyikan for select to authenticated
  using (profile_id = public.my_profile_id());

-- Hapus beberapa notifikasi dari daftar akun ini
create or replace function public.hapus_notif(p_ids uuid[]) returns void
language sql security definer set search_path = public as $$
  insert into public.aktivitas_disembunyikan (profile_id, aktivitas_id)
  select public.my_profile_id(), x from unnest(p_ids) x
  where public.my_profile_id() is not null
  on conflict do nothing
$$;

-- Hapus semua notifikasi akun ini (yang masuk sesudahnya tetap tampil)
create or replace function public.hapus_semua_notif() returns void
language sql security definer set search_path = public as $$
  update public.profiles set inbox_hapus_pada = now(), inbox_dibaca_pada = now() where auth_uid = auth.uid()
$$;

-- ---------------------------------------------------------------------
-- 3. RESET LAPORAN PC SATU TANGGAL
-- ---------------------------------------------------------------------
-- Penjualan yang dihapus saat reset tidak dikirim satu per satu sebagai notifikasi.
create or replace function public.ev_sale() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.catat_aktivitas(new.store_id, new.diinput_oleh,
      case when new.tipe = 'HP' then 'penjualan_hp' else 'penjualan_iot' end,
      case when new.tipe = 'HP' then 'Penjualan HP' else 'Penjualan IoT' end,
      public.label_aktor(new.diinput_oleh, new.store_id) || ': ' || new.nama_produk || ' x' || new.qty
        || ' · ' || public.rp(new.qty * new.harga)
        || coalesce(' · ' || new.kategori_user, '')
        || coalesce(' · ' || new.metode || coalesce(' ' || new.cara_bayar, ''), '')
        || case when new.tanggal <> public.today_wib() then ' · untuk tgl ' || to_char(new.tanggal, 'DD/MM') else '' end,
      new.tanggal, new.id);
  elsif coalesce(current_setting('nka.reset', true), '') <> '1' then
    perform public.catat_aktivitas(old.store_id, public.my_profile_id(), 'hapus_penjualan', 'Penjualan dihapus',
      public.label_aktor(public.my_profile_id(), old.store_id) || ' menghapus ' || old.nama_produk || ' x' || old.qty
        || ' (' || to_char(old.tanggal, 'DD/MM') || ')',
      old.tanggal, old.id);
  end if;
  return null;
end $$;

-- Hapus semua data harian satu toko pada satu tanggal: stok, penjualan, NOSELL, MS Allbrand,
-- display (+foto), activity sosmed, cek limit leasing, dan laporan terkirim.
-- Data istirahat (selfie keluar/kembali) tidak ikut dihapus.
create or replace function public.reset_laporan(p_store int, p_tanggal date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := public.my_profile_id();
  v_pc uuid;
  v_sales int;
begin
  if public.my_role() not in ('tl', 'trainer', 'pic') or not public.can_view_store(p_store) then
    raise exception 'Akses ditolak';
  end if;
  if p_tanggal > public.today_wib() then raise exception 'Tanggal belum terjadi'; end if;

  perform set_config('nka.reset', '1', true);

  delete from public.photos where ref_tabel = 'display_checks'
     and ref_id in (select id from public.display_checks where store_id = p_store and tanggal = p_tanggal);
  delete from public.photos where ref_tabel = 'display_reports'
     and ref_id in (select id from public.display_reports where store_id = p_store and tanggal = p_tanggal);
  delete from public.photos where ref_tabel = 'social_activities'
     and ref_id in (select id from public.social_activities where store_id = p_store and tanggal = p_tanggal);
  delete from public.photos where ref_tabel = 'leasing_checks'
     and ref_id in (select id from public.leasing_checks where store_id = p_store and tanggal = p_tanggal);

  delete from public.sales where store_id = p_store and tanggal = p_tanggal;
  get diagnostics v_sales = row_count;
  delete from public.stock_daily where store_id = p_store and tanggal = p_tanggal;
  delete from public.checkins where store_id = p_store and tanggal = p_tanggal;
  delete from public.competitor_sales_detail where store_id = p_store and tanggal = p_tanggal;
  delete from public.competitor_sales where store_id = p_store and tanggal = p_tanggal;
  delete from public.competitor_prices where store_id = p_store and tanggal = p_tanggal;
  delete from public.display_checks where store_id = p_store and tanggal = p_tanggal;
  delete from public.display_reports where store_id = p_store and tanggal = p_tanggal;
  delete from public.social_activities where store_id = p_store and tanggal = p_tanggal;
  delete from public.leasing_checks where store_id = p_store and tanggal = p_tanggal;
  delete from public.daily_reports where store_id = p_store and tanggal = p_tanggal;
  -- Notifikasi "tidak lapor" tanggal itu juga dihapus agar bisa tercatat ulang
  delete from public.aktivitas where store_id = p_store and tanggal = p_tanggal and jenis = 'tidak_lapor';

  perform set_config('nka.reset', '', true);

  perform public.catat_aktivitas(p_store, v_me, 'laporan', 'Laporan direset',
    public.label_aktor(v_me, p_store) || ' mereset semua laporan tgl ' || to_char(p_tanggal, 'DD/MM')
      || ' (' || v_sales || ' penjualan ikut terhapus). PC perlu mengisi ulang.',
    p_tanggal, null);

  select id into v_pc from public.profiles where store_id = p_store and role = 'pc' and aktif order by created_at limit 1;
  if v_pc is not null then
    insert into public.pengingat (store_id, pc_id, dari, modul, pesan)
    values (p_store, v_pc, v_me, array['stok', 'penjualan', 'ms_allbrand', 'display', 'laporan'],
            'Laporan tgl ' || to_char(p_tanggal, 'DD/MM') || ' direset karena ada yang salah. Silakan isi ulang semua.');
  end if;

  return jsonb_build_object('penjualan_dihapus', v_sales);
end $$;

select 'Tahap 2e siap' as status;
