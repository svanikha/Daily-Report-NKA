import 'package:intl/intl.dart';

/// Semua waktu aplikasi memakai WIB (UTC+7) dalam bentuk DateTime "naif"
/// (tanpa zona) supaya perbandingan tanggal konsisten di semua HP.
DateTime _naive(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);

DateTime wibNow() => _naive(DateTime.now().toUtc().add(const Duration(hours: 7)));
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime wibToday() => dateOnly(wibNow());
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String todayStr() => ymd(wibToday());

DateTime monthStart([DateTime? d]) {
  final x = d ?? wibToday();
  return DateTime(x.year, x.month, 1);
}

DateTime monthEnd([DateTime? d]) {
  final x = d ?? wibToday();
  return DateTime(x.year, x.month + 1, 0);
}

/// Sisa hari di bulan berjalan, termasuk hari ini.
int sisaHari() {
  final t = wibToday();
  return monthEnd(t).day - t.day + 1;
}

/// Awal bulan ini (00.00 WIB) dalam format ISO UTC, untuk filter kolom timestamptz.
String monthStartUtcIso() {
  final m = monthStart();
  return DateTime.utc(m.year, m.month, m.day).subtract(const Duration(hours: 7)).toIso8601String();
}

/// Waktu WIB naif menjadi ISO UTC untuk kolom timestamptz.
String wibToUtcIso(DateTime wib) =>
    DateTime.utc(wib.year, wib.month, wib.day, wib.hour, wib.minute, wib.second)
        .subtract(const Duration(hours: 7))
        .toIso8601String();

/// Mengubah timestamp dari server (UTC) menjadi waktu WIB naif.
DateTime parseWib(String s) => _naive(DateTime.parse(s).toUtc().add(const Duration(hours: 7)));
DateTime parseDate(String s) => dateOnly(DateTime.parse(s));

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
String rupiah(num v) => _rp.format(v);
String angka(num v) => NumberFormat.decimalPattern('id_ID').format(v);
String tgl(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);
String tglPendek(DateTime d) => DateFormat('EEE, d MMM', 'id_ID').format(d);
String tglJam(DateTime d) => DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(d);
String hariTgl(DateTime d) => DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(d);
String namaBulan(DateTime d) => DateFormat('MMMM yyyy', 'id_ID').format(d);

num toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}

Map<String, dynamic> asMap(dynamic v) {
  if (v == null) return <String, dynamic>{};
  return Map<String, dynamic>.from(v as Map);
}

List<Map<String, dynamic>> asList(dynamic v) {
  if (v == null) return <Map<String, dynamic>>[];
  return (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

double pct(num actual, num target) => target <= 0 ? 0 : actual / target * 100;
String pctStr(num actual, num target) => target <= 0 ? '-' : '${pct(actual, target).toStringAsFixed(0)}%';

/// Hanya angka dari teks (untuk input Rupiah).
int digitsOnly(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Format nomor HP Indonesia ke bentuk 628xxx.
String normalizePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('0')) {
    d = '62${d.substring(1)}';
  } else if (d.startsWith('8')) {
    d = '62$d';
  }
  return d;
}

/// PC hanya bisa input/edit data hari ini sampai pukul 23.00 WIB.
bool pcInputOpen() => wibNow().hour < 23;
bool canPcEdit(String tanggal) => tanggal == todayStr() && pcInputOpen();

/// Penjualan HP/IoT boleh diisi/dihapus untuk tanggal berapa pun sampai hari ini.
bool canPcEditSale(String tanggal) => tanggal.compareTo(todayStr()) <= 0;

// ---------------------------------------------------------------------
// Pengingat follow up H+1, H+3, H+7, H+30
// ---------------------------------------------------------------------
const reminderDays = [1, 3, 7, 30];

class ReminderInfo {
  final int h;
  final DateTime due;
  final bool done;
  const ReminderInfo(this.h, this.due, this.done);

  String status(DateTime today) {
    if (done) return 'Selesai';
    if (due.isBefore(today)) return 'Terlewat';
    if (isSameDay(due, today)) return 'Hari ini';
    return 'Terjadwal';
  }
}

List<ReminderInfo> remindersOf(Map<String, dynamic> c) {
  final createdRaw = c['created_at'];
  if (createdRaw == null) return const [];
  final created = dateOnly(parseWib(createdRaw as String));
  final lastRaw = c['last_contacted_at'];
  final last = lastRaw == null ? null : dateOnly(parseWib(lastRaw as String));
  return reminderDays.map((h) {
    final due = addDays(created, h);
    return ReminderInfo(h, due, last != null && !last.isBefore(due));
  }).toList();
}

bool isDueToday(Map<String, dynamic> c, DateTime today) =>
    remindersOf(c).any((r) => !r.done && isSameDay(r.due, today));

bool isOverdue(Map<String, dynamic> c, DateTime today) =>
    remindersOf(c).any((r) => !r.done && r.due.isBefore(today));
