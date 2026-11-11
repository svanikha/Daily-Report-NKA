# Daily Report NKA

Aplikasi laporan harian Product Consultant (PC) OPPO di toko Erafone wilayah OPPO Big Sampit
(8 toko, 3 area: Palangkaraya, Sampit, Pangkalanbun). Dibangun dari pondasi Daily Report OS,
dengan project Supabase dan repo terpisah.

- **Aplikasi:** Flutter (Android + web), dibangun otomatis oleh GitHub Actions
- **Server:** Supabase (database, login, penyimpanan foto)
- **Rencana lengkap:** `Rencana-Teknis-Daily-Report-NKA.md` (di folder induk)

Status: **Tahap 1** (uji coba). PC: stok pagi, penjualan, kompetitor, cek display, istirahat dengan
selfie, kirim laporan & gambar laporan. TL/Trainer/PIC: status laporan semua toko, detail toko,
input Rajawali / PC offday, jadwal offday, produk & harga, target bulanan.

**Update database Tahap 1:** SQL Editor → New query → jalankan berurutan:
1. `supabase/tahap1.sql` → hasil `Tahap 1 siap`
2. `supabase/tahap1b.sql` → hasil `Tahap 1 revisi siap` (MS Allbrand per segmen harga, kalender penjualan)
3. `supabase/tahap1c.sql` → hasil `Notifikasi aktivitas siap` (lihat bagian notifikasi di bawah)
4. `supabase/tahap1d.sql` → checklist display bisa diatur TL, Trainer, PIC
5. `supabase/tahap1e.sql` → MS Allbrand cukup angka per segmen (tanpa tipe)
6. `supabase/tahap1f.sql` → Activity: report sosmed & cek limit leasing
7. `supabase/tahap1g.sql` → notifikasi "PC tidak kirim laporan"
8. `supabase/tahap1h.sql` → batas laporan PC 22.30 WIB, notifikasi PC tidak kirim laporan juga pukul 22.30
9. `supabase/tahap1i.sql` → nama Alwisius, Trainer di laporan, kalender NOSELL, kontribusi Cash/Kredit, kelola akun PC
10. `supabase/tahap1j.sql` → lampu online PC (hijau/merah), login terakhir, riwayat login
11. `supabase/tahap1k.sql` → pilihan istirahat 1 jam atau 3 jam

## Peran

| Peran | Lihat | Atur |
| --- | --- | --- |
| PC (Product Consultant) | tokonya | input harian tokonya |
| TL (Tim Leader) | areanya | input penjualan area, input Rajawali & PC offday/tidak lapor |
| Trainer | areanya | offday, akun PC, checklist display, target toko, produk & harga |
| PIC NKA (Jenni Wijaya) | semua area | semua master, akun TL & Trainer, ekspor gabungan |

## Setup (sekali saja)

### 1. Supabase
1. Buat project baru di supabase.com (misal nama `daily-report-nka`, region Singapore).
2. **SQL Editor → New query** → tempel seluruh isi `supabase/schema.sql` → **Run**.
   Hasil terakhir harus menampilkan: `Daily Report NKA siap: 8 toko, 14 akun, 66 produk, 12 brand`.
3. **Authentication → Sign In / Providers → Email**: matikan **Confirm email**, lalu Save.
   PC, TL, dan Trainer membuat password sendiri saat login pertama.
4. **Authentication → Users → Add user → Create new user** untuk akun PIC NKA:
   - Email: `pic@dailyreportnka.app`
   - Password: password PIC
   - Centang **Auto Confirm User**
5. Catat dari **Project Settings → API**: Project URL dan anon/publishable key.
   Dari **Project Settings → API Keys**: secret key (untuk update di dalam aplikasi).

### 2. GitHub
1. Buat repo baru `Daily-Report-NKA`, lalu push isi folder ini ke branch `main`.
2. Repo → **Settings → Secrets and variables → Actions**:
   - Tab **Variables**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
   - Tab **Secrets**: `SUPABASE_SECRET_KEY`
3. Build pertama otomatis membuat keystore khusus NKA dan menyimpannya ke `ci/debug.keystore`.
   Jangan hapus file ini: tanpa file yang sama, APK baru tidak bisa di-install di atas versi lama.
4. APK ada di tab **Releases** (`DailyReportNKA-v1.0.x.apk`). Push ke branch `uji` menghasilkan
   APK uji coba di tab **Actions → run → Artifacts**.

### 3. Notifikasi aktivitas ke TL, Trainer, PIC (push, muncul walau aplikasi ditutup)
Setiap aktivitas toko (penjualan, hapus penjualan, NOSELL, update stok, MS Allbrand, cek display,
kirim laporan, istirahat mulai / kembali / belum kembali) masuk ke menu **Aktivitas** (ikon lonceng)
dan dikirim sebagai push ke HP TL & Trainer area toko itu serta PIC NKA.

1. **Database:** Database → Extensions → aktifkan **pg_net** dan **pg_cron**. Lalu SQL Editor → jalankan
   `supabase/tahap1c.sql` → hasil `Notifikasi aktivitas siap`.
2. **Firebase:** console.firebase.google.com → Add project (misal `daily-report-nka`, Analytics boleh dimatikan).
   - Project settings → General → **Add app → Android**, package `com.oppobigsampit.daily_report_nka` → Register
     (file google-services.json tidak perlu diunduh).
   - Dari Project settings → General → Your apps, salin ke GitHub → Settings → Secrets and variables →
     Actions → tab **Variables**: `FIREBASE_API_KEY` (Web API Key / current_key), `FIREBASE_APP_ID`
     (App ID `1:...:android:...`), `FIREBASE_SENDER_ID` (Project number / Sender ID), `FIREBASE_PROJECT_ID`.
   - Project settings → **Service accounts → Generate new private key** (file JSON, simpan rahasia).
3. **Edge function:** Supabase → Edge Functions → Deploy a new function → Via editor → nama **`kirim-notif`**
   → tempel isi `supabase/functions/kirim-notif/index.ts` → Deploy. Di pengaturan function matikan
   **Verify JWT**. Lalu Edge Functions → **Secrets** → tambah `FCM_SERVICE_ACCOUNT` = seluruh isi file JSON tadi.
4. Build ulang APK (push ke GitHub), install, lalu **TL, Trainer, dan PIC login ulang** dan izinkan notifikasi
   supaya HP mereka terdaftar untuk menerima push.

### 4. Opsional
- **Versi web** (TL, Trainer, PIC di laptop): isi Variable `FIREBASE_HOSTING_PROJECT` dan Secret
  `FIREBASE_HOSTING_SA` (JSON service account Firebase).

## Akun

PC, TL, dan Trainer cukup memilih nama di layar login. Email di bawah hanya dipakai di belakang layar.

| Nama | Peran | Toko / Area | Email login |
| --- | --- | --- | --- |
| Indra Aryudi | PC | Erafone Seth Adji | indra@dailyreportnka.app |
| Ahmad Syafiq | PC | Erafone RTA Milono | syafiq@dailyreportnka.app |
| Muhammad Syaufi | PC | Erafone G-Obos | syaufi@dailyreportnka.app |
| Nursuci Latifatu Solehah | PC | Erafone Dutamall PKY | nursuci@dailyreportnka.app |
| Era Novallisti | PC | Erafone Pelita | era@dailyreportnka.app |
| Nuriyah | PC | Erafone MT Haryono | nuriyah@dailyreportnka.app |
| Utin Amelia Putri Dewi | PC | Erafone Pangkalanbun | utin@dailyreportnka.app |
| Alwisius Jati Kurniawan | TL | Palangkaraya | alwisiuts@dailyreportnka.app |
| Wiga Bintang Pratama | TL | Sampit | wiga@dailyreportnka.app |
| Yanah | TL | Pangkalanbun | yanah@dailyreportnka.app |
| Istihanah | Trainer | Palangkaraya | istihanah@dailyreportnka.app |
| Brandon Cahyadita | Trainer | Sampit | brandon@dailyreportnka.app |
| Elsa Permata Sari | Trainer | Pangkalanbun | elsa@dailyreportnka.app |
| Jenni Wijaya | PIC NKA | semua area | pic@dailyreportnka.app |

Erafone Rajawali (Palangkaraya) tidak punya PC; penjualannya diinput TL Palangkaraya.

## Aturan penting (dijaga di server)

- PC: stok, kompetitor, dan display hanya untuk hari ini, sampai **22.30 WIB** (laporan malam; notifikasi PC tidak lapor ke atasan pada 22.30).
- Penjualan boleh untuk tanggal lampau, tidak boleh tanggal yang akan datang. Harga diambil dari master produk.
- TL/Trainer bisa melengkapi data harian toko non PC, PC offday, atau PC yang tidak lapor.
- Nomor HP konsumen hanya terlihat oleh PC pemiliknya, TL, Trainer, dan PIC NKA.
- Setiap perubahan produk, harga, dan target tercatat di `audit_log`.
- Lupa password: Trainer (untuk PC areanya) atau PIC NKA melakukan reset; pemilik membuat password baru saat login.

## Struktur kode

```
lib/
  main.dart, config.dart, utils.dart, theme.dart
  services/    session (peran & titik GPS), notifikasi, foto, lokasi, update
  widgets/     komponen UI bersama
  screens/
    login_screen.dart, session_gate.dart
    home_tahap0.dart   beranda sementara Tahap 0
    pc/, admin/        layar Daily Report OS (bahan Tahap 1, belum dipakai)
supabase/schema.sql    tabel, RLS, RPC, data awal (8 toko, 9 titik GPS, 14 akun, 66 produk, 12 brand)
ci/                    patch Android + keystore
.github/workflows/     build APK & web otomatis
```
