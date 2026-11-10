import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils.dart';

/// Notifikasi lokal PC: pengingat stok pagi (10.00 & 10.45), laporan malam
/// (21.00 & 21.45), dan waktu istirahat. Tidak dikirim di hari offday/izin.
class NotifService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static tz.Location? _jkt;

  static const _stokDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'stok',
      'Pengingat stok pagi',
      channelDescription: 'Pengingat update stok harian',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _reportDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'report',
      'Pengingat laporan malam',
      channelDescription: 'Pengingat kirim laporan sebelum 22.00 WIB',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _breakDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'istirahat',
      'Waktu istirahat',
      channelDescription: 'Pengingat agar segera kembali ke toko dan selfie',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _adminDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'admin_alert',
      'Peringatan TL & Trainer',
      channelDescription: 'Peringatan dari server (misal PC belum kembali dari istirahat)',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _breakBaseId = 3000;
  static const _breakMaxId = 3099;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      _jkt = tz.getLocation('Asia/Jakarta');
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'admin_alert',
        'Peringatan TL & Trainer',
        description: 'Peringatan dari server (misal PC belum kembali dari istirahat)',
        importance: Importance.high,
      ));
    } catch (e) {
      debugPrint('Notifikasi gagal disiapkan: $e');
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Menampilkan notifikasi saat ini juga (push dari server saat aplikasi terbuka).
  static Future<void> showNow(String title, String body) async {
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        title: title,
        body: body,
        notificationDetails: _adminDetails,
      );
    } catch (_) {}
  }

  static Future<void> _at(int id, String title, String body, DateTime wib, NotificationDetails details) async {
    final loc = _jkt;
    if (loc == null) return;
    final when = tz.TZDateTime(loc, wib.year, wib.month, wib.day, wib.hour, wib.minute);
    if (!when.isAfter(tz.TZDateTime.now(loc))) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Menjadwalkan ulang semua pengingat PC untuk 7 hari ke depan.
  /// [offdays] tanggal (yyyy-MM-dd) offday/izin. [breakStart] diisi jika sedang istirahat.
  static Future<void> reschedule({
    required Set<String> offdays,
    required bool stokDone,
    required bool laporanDone,
    DateTime? breakStart,
    int breakMenit = 60,
  }) async {
    if (_jkt == null) return;
    try {
      await _plugin.cancelAll();
      final today = wibToday();
      for (var i = 0; i < 7; i++) {
        final d = addDays(today, i);
        if (offdays.contains(ymd(d))) continue;
        if (i > 0 || !stokDone) {
          await _at(2000 + i * 10, 'Update stok hari ini', 'Jangan lupa update stok toko hari ini.',
              DateTime(d.year, d.month, d.day, 10), _stokDetails);
        }
        if (i > 0 || !laporanDone) {
          await _at(2002 + i * 10, 'Waktunya kirim laporan',
              'Lengkapi penjualan, MS Allbrand, dan display, lalu kirim laporan sebelum 22.00 WIB.',
              DateTime(d.year, d.month, d.day, 21), _reportDetails);
          await _at(2003 + i * 10, 'Laporan belum dikirim', '15 menit lagi batas laporan (22.00 WIB).',
              DateTime(d.year, d.month, d.day, 21, 45), _reportDetails);
        }
      }
      if (breakStart != null) await scheduleBreak(breakStart, durasiMenit: breakMenit);
    } catch (e) {
      debugPrint('Gagal menjadwalkan notifikasi: $e');
    }
  }

  /// Pengingat istirahat: 10 menit sebelum habis, saat habis, lalu tiap 15 menit sampai 22.00 WIB.
  static Future<void> scheduleBreak(DateTime mulaiWib, {int durasiMenit = 60}) async {
    try {
      await cancelBreak();
      final label = durasiMenit == 60 ? '1 jam' : '2 jam';
      final batas = DateTime(mulaiWib.year, mulaiWib.month, mulaiWib.day, 22);
      await _at(_breakBaseId, 'Waktu istirahat hampir habis', '10 menit lagi waktu istirahat $label habis.',
          mulaiWib.add(Duration(minutes: durasiMenit - 10)), _breakDetails);
      var id = _breakBaseId + 1;
      for (var m = durasiMenit; id <= _breakMaxId; m += 15) {
        final t = mulaiWib.add(Duration(minutes: m));
        if (t.isAfter(batas)) break;
        await _at(id++, 'Waktu istirahat $label habis', 'Segera kembali ke toko dan selfie.', t, _breakDetails);
      }
    } catch (e) {
      debugPrint('Gagal menjadwalkan pengingat istirahat: $e');
    }
  }

  static Future<void> cancelBreak() async {
    for (var id = _breakBaseId; id <= _breakMaxId; id++) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }
}
