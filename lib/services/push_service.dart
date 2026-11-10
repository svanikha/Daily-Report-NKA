import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'notif_service.dart';
import 'session.dart';

/// Push notification dari server (Firebase) - hanya untuk HP admin:
/// peringatan PC yang istirahat lebih dari 3 jam.
class PushService {
  static bool _ready = false;

  /// Dipasang oleh dashboard admin: membuka halaman Pesan Masuk saat push diketuk.
  static void Function()? onOpenInbox;

  static Future<void> init() async {
    if (!FirebaseConfig.isConfigured) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: FirebaseConfig.apiKey,
          appId: FirebaseConfig.appId,
          messagingSenderId: FirebaseConfig.messagingSenderId,
          projectId: FirebaseConfig.projectId,
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Firebase gagal disiapkan: $e');
    }
  }

  /// Dipanggil saat admin masuk: simpan token HP admin ke server.
  static Future<void> registerAdmin() async {
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token != null) await Session.db.rpc('set_fcm_token', params: {'p_token': token});
      fm.onTokenRefresh.listen((t) => Session.db.rpc('set_fcm_token', params: {'p_token': t}));
      // Saat aplikasi admin sedang terbuka, push tidak tampil otomatis: tampilkan lewat notifikasi lokal.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) NotifService.showNow(n.title ?? 'Peringatan', n.body ?? '');
      });
      // Push diketuk saat aplikasi di latar belakang / tertutup -> buka Pesan Masuk
      FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpenInbox?.call());
      final initial = await fm.getInitialMessage();
      if (initial != null) onOpenInbox?.call();
    } catch (e) {
      debugPrint('Gagal mendaftarkan push admin: $e');
    }
  }

  /// Saat admin keluar, hapus token agar HP ini tidak menerima peringatan lagi.
  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      await Session.db.rpc('set_fcm_token', params: {'p_token': null});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
