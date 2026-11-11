import 'dart:async';

import 'package:flutter/material.dart';

import 'session.dart';

/// Status online: selama aplikasi terbuka (di layar), kirim tanda aktif ke server setiap 2 menit
/// dan setiap aplikasi kembali dibuka. Dashboard atasan menganggap "online" jika tanda aktif
/// terakhir kurang dari 5 menit yang lalu.
class PresenceService {
  static const intervalPing = Duration(minutes: 2);

  /// Batas dianggap online.
  static const batasOnline = Duration(minutes: 5);

  static bool _started = false;
  static bool _foreground = true;
  static Timer? _timer;

  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_Lifecycle());
    _timer = Timer.periodic(intervalPing, (_) {
      if (_foreground) ping();
    });
  }

  static void stop() => _timer?.cancel();

  static Future<void> ping() async {
    if (Session.current == null) return;
    try {
      await Session.db.rpc('ping_online');
    } catch (_) {}
  }

  /// Setelah login berhasil.
  static Future<void> login() async {
    try {
      await Session.db.rpc('catat_login', params: {'p_jenis': 'login'});
    } catch (_) {}
  }

  /// Aplikasi dibuka dengan sesi login yang tersimpan.
  static Future<void> buka() async {
    try {
      await Session.db.rpc('catat_login', params: {'p_jenis': 'buka'});
    } catch (_) {}
  }

  /// Sebelum keluar (logout).
  static Future<void> logout() async {
    try {
      await Session.db.rpc('catat_logout');
    } catch (_) {}
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PresenceService._foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) PresenceService.ping();
  }
}

/// Status online seseorang dari kolom profiles (last_seen, last_login, logged_in, auth_uid).
class StatusOnline {
  final bool online;
  final bool pernahLogin;
  final bool masihLogin;
  final DateTime? lastSeen; // WIB
  final DateTime? lastLogin; // WIB

  const StatusOnline({
    required this.online,
    required this.pernahLogin,
    required this.masihLogin,
    this.lastSeen,
    this.lastLogin,
  });

  factory StatusOnline.dari(Map<String, dynamic> p, DateTime Function(String) parse) {
    final seen = p['last_seen'] == null ? null : parse('${p['last_seen']}');
    final login = p['last_login'] == null ? null : parse('${p['last_login']}');
    final masih = p['logged_in'] == true && p['auth_uid'] != null;
    final serverSeen = p['last_seen'] == null ? null : DateTime.parse('${p['last_seen']}').toUtc();
    final online = masih &&
        serverSeen != null &&
        DateTime.now().toUtc().difference(serverSeen) < PresenceService.batasOnline;
    return StatusOnline(
      online: online,
      pernahLogin: login != null || p['auth_uid'] != null,
      masihLogin: masih,
      lastSeen: seen,
      lastLogin: login,
    );
  }
}
