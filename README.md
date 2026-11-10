# Daily Report NKA

Aplikasi laporan harian Product Consultant (PC) OPPO di toko Erafone wilayah OPPO Big Sampit
(8 toko, 3 area: Palangkaraya, Sampit, Pangkalanbun). Dibangun dari pondasi Daily Report OS,
dengan project Supabase dan repo terpisah.

- **Aplikasi:** Flutter (Android + web), dibangun otomatis oleh GitHub Actions
- **Server:** Supabase (database, login, penyimpanan foto)
- **Rencana lengkap:** `Rencana-Teknis-Daily-Report-NKA.md` (di folder induk)

Status: **Tahap 0**. Login semua peran sudah jalan dan menampilkan beranda sementara
(nama, peran, toko/area, titik GPS). Menu laporan dibuat di Tahap 1.

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

### 3. Opsional
- **Push notification** (peringatan istirahat ke TL/Trainer, Tahap 2): buat project Firebase,
  tambah aplikasi Android `com.oppobigsampit.daily_report_nka`, isi Variables
  `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`.
- **Versi web** (TL, Trainer, PIC di laptop): isi Variable `FIREBASE_HOSTING_PROJECT` dan Secret
  `FIREBASE_HOSTING_SA` (JSON service account Firebase).
- Edge function `supabase/functions/cek-istirahat` masih versi Daily Report OS dan akan disesuaikan di Tahap 2.

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
| Alwisiuts Jati Kurniawan | TL | Palangkaraya | alwisiuts@dailyreportnka.app |
| Wiga Bintang Pratama | TL | Sampit | wiga@dailyreportnka.app |
| Yanah | TL | Pangkalanbun | yanah@dailyreportnka.app |
| Istihanah | Trainer | Palangkaraya | istihanah@dailyreportnka.app |
| Brandon Cahyadita | Trainer | Sampit | brandon@dailyreportnka.app |
| Elsa Permata Sari | Trainer | Pangkalanbun | elsa@dailyreportnka.app |
| Jenni Wijaya | PIC NKA | semua area | pic@dailyreportnka.app |

Erafone Rajawali (Palangkaraya) tidak punya PC; penjualannya diinput TL Palangkaraya.

## Aturan penting (dijaga di server)

- PC: stok, kompetitor, dan display hanya untuk hari ini, sampai **22.00 WIB**.
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
