import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils.dart';

/// Notifikasi lokal: pengingat follow up konsumen, alarm report 22.00 WIB,
/// dan pengingat waktu istirahat.
class NotifService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static tz.Location? _jkt;
  static String? _pending;
  static void Function(String? payload)? onTapListener;

  /// Jam kirim pengingat follow up (ditentukan sistem, tidak diatur PC).
  static const followUpHour = 9;

  static const _followDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'followup',
      'Follow up konsumen',
      channelDescription: 'Pengingat follow up H+1, H+3, H+7, H+30',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static const _reportDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'report',
      'Pengingat report harian',
      channelDescription: 'Alarm pukul 22.00 WIB jika report belum diisi',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _breakDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'istirahat',
      'Waktu istirahat',
      channelDescription: 'Pengingat agar segera klik Kembali ke Toko',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _adminDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'admin_alert',
      'Peringatan RBM',
      channelDescription: 'Peringatan istirahat PC lebih dari 3 jam',
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
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (r) => _handle(r.payload),
      );
      // Channel untuk push dari server (Firebase) agar tampil sebagai notifikasi penting.
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'admin_alert',
        'Peringatan RBM',
        description: 'Peringatan istirahat PC lebih dari 3 jam',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'pesan_masuk',
        'Pesan masuk',
        description: 'Laporan penjualan, istirahat, dan cek limit leasing dari PC',
        importance: Importance.high,
      ));
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _pending = launch?.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('Notifikasi gagal disiapkan: $e');
    }
  }

  static void _handle(String? payload) {
    final l = onTapListener;
    if (l != null) {
      l(payload);
    } else {
      _pending = payload;
    }
  }

  static String? takePending() {
    final p = _pending;
    _pending = null;
    return p;
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

  /// Menampilkan notifikasi saat ini juga (dipakai untuk push saat aplikasi admin terbuka).
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

  static Future<void> _at(int id, String title, String body, DateTime wib, NotificationDetails details, String payload) async {
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
      payload: payload,
    );
  }

  /// Hari kerja berikutnya (melewati offday/izin), mulai dari [d].
  static DateTime _workDay(DateTime d, Set<String> offdays) {
    var x = d;
    for (var i = 0; i < 14 && offdays.contains(ymd(x)); i++) {
      x = addDays(x, 1);
    }
    return x;
  }

  /// Menjadwalkan ulang semua notifikasi PC.
  /// [contacts] berisi id, nama, kategori, created_at, last_contacted_at.
  /// [offdays] berisi tanggal (yyyy-MM-dd) offday/izin PC.
  /// [breakStart] waktu mulai istirahat (WIB) jika sedang istirahat.
  static Future<void> reschedule({
    required List<Map<String, dynamic>> contacts,
    required bool todayDone,
    Set<String> offdays = const {},
    DateTime? breakStart,
    int breakMenit = 180,
  }) async {
    if (_jkt == null) return;
    try {
      await _plugin.cancelAll();
      final today = wibToday();

      // Pengingat follow up: notifikasi teks biasa. Yang jatuh di offday dipindah ke hari kerja berikutnya.
      final byDay = <DateTime, List<MapEntry<Map<String, dynamic>, int>>>{};
      for (final c in contacts) {
        for (final r in remindersOf(c)) {
          if (r.done || r.due.isBefore(today)) continue;
          if (r.due.difference(today).inDays > 40) continue;
          final day = _workDay(r.due, offdays);
          byDay.putIfAbsent(day, () => []).add(MapEntry(c, r.h));
        }
      }
      final days = byDay.keys.toList()..sort();
      var id = 1000;
      for (final d in days) {
        final list = byDay[d]!;
        if (list.length == 1) {
          final c = list.first.key;
          await _at(
            id++,
            'Follow up H+${list.first.value}: ${c['nama']}',
            '${c['nama']} (${c['kategori'] ?? '-'}). Ketuk untuk menghubungi.',
            DateTime(d.year, d.month, d.day, followUpHour),
            _followDetails,
            'contact:${c['id']}',
          );
        } else {
          final names = list.take(3).map((e) => '${e.key['nama']} (H+${e.value})').join(', ');
          final more = list.length > 3 ? ' dan ${list.length - 3} lainnya' : '';
          await _at(
            id++,
            'Follow up hari ini: ${list.length} konsumen',
            '$names$more. Ketuk untuk menghubungi.',
            DateTime(d.year, d.month, d.day, followUpHour),
            _followDetails,
            'followup',
          );
        }
      }

      // Alarm report pukul 22.00 WIB (1 jam sebelum batas input 23.00), kecuali hari offday.
      for (var i = 0; i < 7; i++) {
        final d = addDays(today, i);
        if (offdays.contains(ymd(d))) continue;
        await _at(
          2000 + i,
          'Waktunya kirim laporan harian',
          'Lengkapi Report, Activity, dan Checklist (batas 23.00 WIB), lalu kirim gambar laporan ke grup.',
          DateTime(d.year, d.month, d.day, 22),
          _reportDetails,
          'laporan',
        );
      }

      if (breakStart != null) await scheduleBreak(breakStart, durasiMenit: breakMenit);
    } catch (e) {
      debugPrint('Gagal menjadwalkan notifikasi: $e');
    }
  }

  /// Pengingat istirahat: 15 menit sebelum durasi habis, saat habis,
  /// lalu tiap 15 menit sampai 23.00 WIB. [durasiMenit] = 60 atau 180.
  static Future<void> scheduleBreak(DateTime mulaiWib, {int durasiMenit = 180}) async {
    try {
      await cancelBreak();
      final label = durasiMenit == 60 ? '1 jam' : '3 jam';
      final batas = DateTime(mulaiWib.year, mulaiWib.month, mulaiWib.day, 23);
      await _at(_breakBaseId, 'Waktu istirahat hampir habis', '15 menit lagi waktu istirahat $label habis.',
          mulaiWib.add(Duration(minutes: durasiMenit - 15)), _breakDetails, 'istirahat');
      var id = _breakBaseId + 1;
      for (var m = durasiMenit; id <= _breakMaxId; m += 15) {
        final t = mulaiWib.add(Duration(minutes: m));
        if (t.isAfter(batas)) break;
        await _at(id++, 'Waktu istirahat $label habis', 'Segera klik Kembali ke Toko.', t, _breakDetails, 'istirahat');
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
