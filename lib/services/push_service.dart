import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'notif_service.dart';
import 'session.dart';

/// Push notification dari server (Firebase) untuk HP TL, Trainer, dan PIC NKA:
/// semua aktivitas toko (penjualan, stok, MS Allbrand, display, laporan, istirahat).
/// Tetap muncul walau aplikasi ditutup.
class PushService {
  static bool _ready = false;
  static bool _listening = false;

  /// Token push HP ini (null = belum terdaftar).
  static String? tokenHp;

  /// Firebase siap dan HP sudah punya token push.
  static bool get terdaftar => _ready && tokenHp != null;
  static bool get siap => _ready;

  /// Dipasang oleh dashboard admin: membuka halaman Pesan Masuk saat push diketuk.
  static void Function()? onOpenInbox;

  /// Dipanggil saat push diketuk, membawa data push (misal jenis 'pesan' + id pengirim).
  static void Function(Map<String, dynamic> data)? onOpen;

  static void _buka(Map<String, dynamic> data) {
    if (onOpen != null) {
      onOpen!(data);
    } else {
      onOpenInbox?.call();
    }
  }

  /// Pesan error terakhir pendaftaran push (ditampilkan di layar Akses notifikasi).
  static String? galat;

  static Future<void> init() async {
    if (!FirebaseConfig.isConfigured) {
      galat = 'Konfigurasi Firebase kosong di build ini';
      return;
    }
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
      galat = 'Firebase gagal disiapkan: $e';
      debugPrint(galat);
    }
  }

  /// Dipanggil saat masuk (atasan maupun PC): simpan token HP ke server.
  /// PC menerima pengingat dari TL / Trainer / PIC; atasan menerima semua aktivitas toko.
  static Future<void> register() => registerAdmin();

  /// Simpan token HP ke server.
  static Future<void> registerAdmin() async {
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      String? token;
      try {
        token = await fm.getToken().timeout(const Duration(seconds: 20));
      } catch (e) {
        galat = 'Gagal mengambil token Firebase: $e';
        rethrow;
      }
      if (token == null) {
        galat = 'Firebase tidak memberi token (null)';
        return;
      }
      try {
        await Session.db.rpc('set_fcm_token', params: {'p_token': token});
      } catch (e) {
        galat = 'Token didapat tetapi gagal disimpan ke server: $e';
        rethrow;
      }
      tokenHp = token;
      galat = null;
      // Beri tahu server bahwa HP ini punya channel "Notifikasi penting" (prioritas tertinggi:
      // spanduk, layar kunci, getar). Jika server belum mendukung (tahap2g.sql), abaikan.
      try {
        await Session.db.rpc('set_notif_channel', params: {'p_channel': NotifService.kanalPenting});
      } catch (_) {}
      if (_listening) return;
      _listening = true;
      fm.onTokenRefresh.listen((t) {
        tokenHp = t;
        Session.db.rpc('set_fcm_token', params: {'p_token': t});
      });
      // Saat aplikasi sedang terbuka, push tidak tampil otomatis: tampilkan lewat notifikasi lokal.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) NotifService.showNow(n.title ?? 'Peringatan', n.body ?? '');
      });
      // Push diketuk saat aplikasi di latar belakang / tertutup -> buka Pesan Masuk
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _buka(m.data));
      final initial = await fm.getInitialMessage();
      if (initial != null) _buka(initial.data);
    } catch (e) {
      galat ??= 'Gagal mendaftarkan push: $e';
      debugPrint(galat);
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
