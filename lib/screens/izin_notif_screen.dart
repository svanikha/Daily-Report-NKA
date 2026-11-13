import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notif_service.dart';
import '../services/push_service.dart';
import '../services/session.dart';
import '../utils.dart';
import '../widgets/widgets.dart';

const _paket = 'com.oppobigsampit.daily_report_nka';

/// Status akses yang dibutuhkan agar notifikasi tampil di layar kunci, spanduk, dan bilah notifikasi.
class StatusIzin {
  final bool notifikasi;
  final bool baterai;
  const StatusIzin({required this.notifikasi, required this.baterai});
  bool get lengkap => notifikasi && baterai;

  static Future<StatusIzin> cek() async {
    var notif = await NotifService.aktif();
    var bat = true;
    try {
      notif = notif && await Permission.notification.isGranted;
      bat = await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {}
    return StatusIzin(notifikasi: notif, baterai: bat);
  }
}

/// Dipanggil beranda PC & atasan: jika akses notifikasi belum lengkap, buka layar pengaturan
/// (sekali per pembukaan aplikasi).
class IzinNotif {
  static bool _sudahDitawarkan = false;

  static Future<void> tawarkan(BuildContext context) async {
    if (kIsWeb || _sudahDitawarkan) return;
    _sudahDitawarkan = true;
    final s = await StatusIzin.cek();
    if (s.lengkap || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IzinNotifScreen(otomatis: true)));
  }
}

/// Layar "Akses notifikasi": izin notifikasi, tampilan layar kunci & spanduk, pengecualian
/// hemat baterai, mulai otomatis (khusus OPPO/realme/Xiaomi/vivo), dan tes push dari server.
class IzinNotifScreen extends StatefulWidget {
  /// Dibuka otomatis karena akses belum lengkap (tampilkan tombol "Nanti saja").
  final bool otomatis;
  const IzinNotifScreen({super.key, this.otomatis = false});

  @override
  State<IzinNotifScreen> createState() => _IzinNotifScreenState();
}

class _IzinNotifScreenState extends State<IzinNotifScreen> with WidgetsBindingObserver {
  StatusIzin? _s;
  bool _tes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cek();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kembali dari layar Pengaturan HP: cek ulang
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cek();
  }

  Future<void> _cek() async {
    final s = await StatusIzin.cek();
    if (mounted) setState(() => _s = s);
  }

  Future<void> _izinNotif() async {
    try {
      final st = await Permission.notification.request();
      await NotifService.requestPermission();
      if (st.isPermanentlyDenied) await _bukaPengaturanNotif();
    } catch (_) {
      await _bukaPengaturanNotif();
    }
    await PushService.register();
    _cek();
  }

  Future<void> _baterai() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      await _intent('android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS');
    }
    _cek();
  }

  Future<void> _bukaPengaturanNotif() => _intent(
        'android.settings.APP_NOTIFICATION_SETTINGS',
        args: {'android.provider.extra.APP_PACKAGE': _paket, 'app_package': _paket},
      );

  Future<void> _bukaChannel() => _intent(
        'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
        args: {
          'android.provider.extra.APP_PACKAGE': _paket,
          'android.provider.extra.CHANNEL_ID': NotifService.kanalPenting,
        },
      );

  Future<void> _bukaInfoAplikasi() async {
    try {
      await openAppSettings();
    } catch (_) {
      await _intent('android.settings.APPLICATION_DETAILS_SETTINGS', data: 'package:$_paket');
    }
  }

  Future<void> _intent(String action, {Map<String, dynamic>? args, String? data}) async {
    try {
      await AndroidIntent(action: action, arguments: args, data: data).launch();
    } catch (_) {
      try {
        await openAppSettings();
      } catch (_) {}
    }
  }

  Future<void> _tesPush() async {
    setState(() => _tes = true);
    try {
      await PushService.register();
      final r = asMap(await Session.db.rpc('tes_notif'));
      if (!mounted) return;
      showMsg(
        context,
        r['ok'] == true
            ? 'Push percobaan dikirim. Kunci layar HP sekarang dan tunggu ±10 detik.'
            : '${r['pesan'] ?? 'Gagal mengirim push percobaan'}',
      );
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _tes = false);
  }

  Future<void> _tesLokal() => NotifService.showNow('Tes notifikasi lokal', 'Jika ini muncul sebagai spanduk, tampilan sudah benar.');

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Akses notifikasi')),
      bottomNavigationBar: widget.otomatis
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(s?.lengkap == true ? 'Selesai' : 'Nanti saja'),
                ),
              ),
            )
          : null,
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              InfoBanner(
                s.lengkap
                    ? 'Akses utama sudah aktif. Pastikan juga langkah 3 dan 4 sesuai merek HP, lalu tekan Tes notifikasi.'
                    : 'Agar notifikasi tampil di layar kunci, spanduk atas, dan bilah notifikasi walau aplikasi '
                        'ditutup, aktifkan semua langkah di bawah.',
                icon: s.lengkap ? Icons.verified : Icons.notifications_active,
                color: s.lengkap ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              _langkah(
                1,
                'Izinkan notifikasi',
                'Izin utama agar aplikasi boleh menampilkan notifikasi.',
                s.notifikasi,
                'Izinkan',
                _izinNotif,
              ),
              _langkah(
                2,
                'Abaikan penghemat baterai',
                'Agar push tetap masuk walau aplikasi ditutup atau HP terkunci lama. Pilih "Izinkan".',
                s.baterai,
                'Atur',
                _baterai,
              ),
              _langkah(
                3,
                'Tampil di layar kunci & spanduk',
                'Buka "Notifikasi penting", lalu aktifkan: Spanduk/Pop-up, Layar kunci (tampilkan isi), Suara, dan Getar. '
                    'Di HP OPPO/realme: Pengaturan > Notifikasi & bilah status > Daily Report NKA.',
                null,
                'Buka',
                () async {
                  await _bukaChannel();
                },
                tambahan: TextButton(onPressed: _bukaPengaturanNotif, child: const Text('Semua notifikasi aplikasi')),
              ),
              _langkah(
                4,
                'Mulai otomatis & jalan di latar belakang',
                'Khusus OPPO, realme, Xiaomi, vivo: Info aplikasi > Penggunaan baterai > aktifkan "Izinkan aktivitas '
                    'latar belakang" dan "Mulai otomatis". Tanpa ini, push bisa tertahan saat aplikasi ditutup.',
                null,
                'Info aplikasi',
                _bukaInfoAplikasi,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('5. Tes notifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      PushService.terdaftar
                          ? 'HP ini terdaftar untuk push. Tekan tombol di bawah, lalu kunci layar: notifikasi harus '
                              'muncul di layar kunci dan bilah notifikasi.'
                          : 'HP ini belum terdaftar untuk push. Izinkan notifikasi (langkah 1), lalu tekan Tes.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _tes ? null : _tesPush,
                          icon: busyIcon(_tes, Icons.send),
                          label: const Text('Tes dari server'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _tesLokal,
                          icon: const Icon(Icons.notifications),
                          label: const Text('Tes spanduk'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _langkah(int no, String judul, String ket, bool? ok, String tombol, Future<void> Function() aksi,
      {Widget? tambahan}) {
    final c = ok == null ? Colors.blueGrey : (ok ? Colors.green.shade700 : Colors.red.shade700);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 12, backgroundColor: c, child: Text('$no', style: const TextStyle(color: Colors.white, fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(child: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (ok != null)
              Pill(ok ? 'Aktif' : 'Belum', color: c),
          ]),
          const SizedBox(height: 4),
          Text(ket, style: Theme.of(context).textTheme.bodySmall),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (tambahan != null) tambahan,
            FilledButton.tonal(onPressed: aksi, child: Text(ok == true ? 'Buka lagi' : tombol)),
          ]),
        ]),
      ),
    );
  }
}
