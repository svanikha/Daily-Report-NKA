import '../services/session.dart';
import '../utils.dart';

/// Cara bayar penjualan HP (disimpan di sales.metode + sales.cara_bayar).
const cashViaList = ['Transfer', 'Tunai'];
const kreditViaList = ['Avanto', 'Kredivo', 'HCI', 'Indodana', 'Kreditplus', 'Akulaku', 'Yesscredit'];

/// Kategori user (pembeli) penjualan HP & IoT, disimpan di sales.kategori_user.
const kategoriUserList = ['Walk-in', 'Databased', 'Online'];

/// Leasing untuk cek limit (sama dengan pilihan Kredit di penjualan).
const leasingList = kreditViaList;

/// Jenis activity PC (FB Marketplace, TikTok Live, IG/WA story, dan activity baru buatan atasan).
/// Daftar dimuat dari tabel jenis_activity (tahap2m.sql); 4 jenis bawaan dipakai jika belum dimuat.
class SosmedDef {
  final String kode;
  final String nama;
  final String satuan;

  /// null = semua area
  final int? areaId;
  final bool aktif;
  const SosmedDef(this.kode, this.nama, this.satuan, {this.areaId, this.aktif = true});
  String get label => nama;

  factory SosmedDef.dari(Map<String, dynamic> m) => SosmedDef(
        '${m['kode']}',
        '${m['nama']}',
        '${m['satuan'] ?? 'kali'}',
        areaId: m['area_id'] == null ? null : toNum(m['area_id']).toInt(),
        aktif: m['aktif'] != false,
      );
}

const _sosmedBawaan = [
  SosmedDef('fb_posting', 'FB Marketplace - Posting', 'kali'),
  SosmedDef('tiktok_live', 'TikTok - Live', 'kali'),
  SosmedDef('ig_story', 'Instagram - Update story', 'kali'),
  SosmedDef('wa_story', 'WhatsApp - Update story', 'kali'),
];

/// Semua jenis activity yang dikenal (termasuk yang sudah dinonaktifkan, untuk label riwayat).
List<SosmedDef> semuaJenisActivity = [..._sosmedBawaan];

/// Jenis activity aktif (semua area).
List<SosmedDef> get sosmedDefs => semuaJenisActivity.where((d) => d.aktif).toList();

/// Jenis activity aktif yang berlaku di satu area (umum + khusus area itu).
List<SosmedDef> jenisActivityArea(int? areaId) =>
    sosmedDefs.where((d) => d.areaId == null || d.areaId == areaId).toList();

/// Muat ulang daftar jenis activity dari server (aman dipanggil berkali-kali).
Future<void> muatJenisActivity() async {
  try {
    final rows = asList(await Session.db.from('jenis_activity').select('kode,nama,satuan,area_id,aktif,urutan').order('urutan'));
    if (rows.isNotEmpty) semuaJenisActivity = [for (final r in rows) SosmedDef.dari(r)];
  } catch (_) {
    // tahap2m.sql belum dijalankan: tetap pakai 4 jenis bawaan
  }
}

SosmedDef? sosmedByKode(String? kode) {
  for (final d in semuaJenisActivity) {
    if (d.kode == kode) return d;
  }
  return null;
}

/// Batas waktu laporan malam (WIB). Update stok tidak punya batas jam.
/// Pilihan durasi istirahat (menit): 1 jam atau 3 jam.
const durasiIstirahat = [60, 180];

/// "1 jam", "3 jam" (data lama 120 menit tampil "2 jam").
String labelDurasi(num menit) => '${menit ~/ 60} jam';

/// Batas laporan malam PC: 22.30 WIB. Pada jam yang sama, PC yang belum kirim laporan
/// dikirim notifikasi "PC tidak kirim laporan" ke TL, Trainer, PIC.
const batasLaporanText = '22.30';

/// Waktu batas laporan pada tanggal tertentu (WIB).
DateTime batasLaporanPada(DateTime tanggal) => DateTime(tanggal.year, tanggal.month, tanggal.day, 22, 30);

/// Sudah lewat 22.30 WIB? [wib] default sekarang.
bool lewatBatasLaporan([DateTime? wib]) {
  final w = wib ?? wibNow();
  return w.hour * 60 + w.minute >= 22 * 60 + 30;
}

/// Segmen harga MS Allbrand.
const segmenList = ['lt3', '3to6', 'gt6'];
const segmenLabel = {'lt3': '< 3 jt', '3to6': '3 jt - 6 jt', 'gt6': '6 jt up'};

/// Segmen yang berlaku untuk satu brand di MS Allbrand (Apple hanya 6 jt up).
List<String> segmenBrand(String nama) => nama.toLowerCase() == 'apple' ? const ['gt6'] : segmenList;

/// Hari kerja & timegone dalam satu bulan.
/// timegone = tanggal hari ini / jumlah hari di bulan itu (10/30 = 33%).
/// sisa hari kerja = hari berjalan s.d. akhir bulan (termasuk hari ini) dikurangi offday PC.
class HariKerja {
  final int hariKe;
  final int totalHari;
  final int sisaHariKerja;
  final int offdaySisa;
  const HariKerja({required this.hariKe, required this.totalHari, required this.sisaHariKerja, required this.offdaySisa});

  factory HariKerja.dari(DateTime tanggal, {int offdaySisa = 0}) {
    final total = monthEnd(tanggal).day;
    final sisa = total - tanggal.day + 1 - offdaySisa;
    return HariKerja(hariKe: tanggal.day, totalHari: total, sisaHariKerja: sisa < 0 ? 0 : sisa, offdaySisa: offdaySisa);
  }

  double get timegone => hariKe / totalHari * 100;
  String get timegoneText => '$hariKe/$totalHari = ${timegone.toStringAsFixed(0)}%';

  /// Kekurangan dibagi sisa hari kerja (0 jika sudah tercapai atau tidak ada hari kerja).
  num perHari(num target, num capai) {
    final kurang = target - capai;
    if (kurang <= 0 || sisaHariKerja <= 0) return 0;
    return kurang / sisaHariKerja;
  }
}

/// Jenis target bulanan per toko.
class TargetDef {
  final String jenis;
  final String label;
  final bool rupiah;
  const TargetDef(this.jenis, this.label, {this.rupiah = false});
}

const targetDefs = [
  TargetDef('unit', 'Unit HP'),
  TargetDef('value', 'Value HP', rupiah: true),
  TargetDef('fokus_a7pro', 'Tipe fokus A7 Pro'),
  TargetDef('fokus_reno16', 'Tipe fokus Reno 16'),
  TargetDef('iot', 'IoT (unit)'),
];

/// Satu toko pada satu tanggal: konteks semua layar input harian.
/// Dipakai PC (tokonya sendiri, hari ini) dan TL/Trainer/PIC (toko di cakupannya).
class TokoHari {
  final int storeId;
  final String toko;
  final String area;
  final String? pcId;
  final String? pcNama;
  final bool punyaPc;
  final DateTime tanggal;

  /// offday | izin | null
  final String? libur;

  const TokoHari({
    required this.storeId,
    required this.toko,
    required this.area,
    this.pcId,
    this.pcNama,
    this.punyaPc = true,
    required this.tanggal,
    this.libur,
  });

  factory TokoHari.dariPc(Profile p, {String? libur}) => TokoHari(
        storeId: p.storeId!,
        toko: p.toko,
        area: p.area,
        pcId: p.id,
        pcNama: p.nama,
        tanggal: wibToday(),
        libur: libur,
      );

  factory TokoHari.dariStatus(Map<String, dynamic> m, DateTime tanggal) => TokoHari(
        storeId: toNum(m['store_id']).toInt(),
        toko: '${m['toko'] ?? ''}',
        area: '${m['area'] ?? ''}',
        pcId: m['pc_id'] as String?,
        pcNama: m['pc'] as String?,
        punyaPc: m['punya_pc'] != false,
        tanggal: tanggal,
        libur: m['libur'] as String?,
      );

  /// Toko yang sama pada tanggal lain (status libur tanggal itu tidak diketahui).
  TokoHari padaTanggal(DateTime d) => TokoHari(
        storeId: storeId,
        toko: toko,
        area: area,
        pcId: pcId,
        pcNama: pcNama,
        punyaPc: punyaPc,
        tanggal: dateOnly(d),
      );

  TokoHari denganLibur(String? l) => TokoHari(
        storeId: storeId,
        toko: toko,
        area: area,
        pcId: pcId,
        pcNama: pcNama,
        punyaPc: punyaPc,
        tanggal: tanggal,
        libur: l,
      );

  String get tgl => ymd(tanggal);
  bool get hariIni => isSameDay(tanggal, wibToday());

  /// Sama dengan aturan server can_write_daily (stok, kompetitor, display, laporan).
  bool get bolehIsiHarian {
    final me = Session.current;
    if (me == null) return false;
    final today = wibToday();
    if (tanggal.isAfter(today)) return false;
    if (me.isPic) return true;
    if (me.isPc) return hariIni && !lewatBatasLaporan();
    if (me.isTl || me.isTrainer) {
      return !punyaPc || libur != null || tanggal.isBefore(today) || lewatBatasLaporan();
    }
    return false;
  }

  /// Sama dengan aturan server can_write_sales.
  bool get bolehIsiPenjualan {
    final me = Session.current;
    final today = wibToday();
    if (me == null || tanggal.isAfter(today)) return false;
    // PC: hanya bulan berjalan (tgl 1 s.d. hari ini), sama dengan server can_write_sales
    if (me.isPc) return tanggal.year == today.year && tanggal.month == today.month;
    return me.isPic || me.isTl;
  }

  /// Alasan tidak bisa mengisi data harian (untuk ditampilkan).
  String get alasanTerkunci {
    final me = Session.current;
    if (me != null && me.isPc) return 'Input hanya bisa untuk hari ini sampai pukul 22.30 WIB.';
    if (me != null && me.isTrainer && !bolehIsiHarian) {
      return 'Trainer/TL hanya melengkapi data toko non PC, PC offday, atau PC yang tidak lapor (setelah 22.30 WIB).';
    }
    return 'TL/Trainer hanya melengkapi data toko non PC, PC offday, atau PC yang tidak lapor (setelah 22.30 WIB).';
  }
}

String jamMenit(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
