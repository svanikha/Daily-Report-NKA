import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'session.dart';

/// Update otomatis di dalam aplikasi.
///
/// GitHub Actions mengunggah APK terbaru + latest.json ke bucket publik "apk" di Supabase.
/// Aplikasi mengecek versi saat dibuka, setiap kembali dari latar belakang, dan tiap 30 menit.
/// Jika ada versi baru, APK langsung diunduh di dalam aplikasi (dengan progres), lalu layar
/// pasang Android terbuka. Android selalu meminta satu ketukan "Perbarui" dari pengguna;
/// pemasangan tanpa ketukan sama sekali tidak diizinkan untuk aplikasi di luar Play Store.
class UpdateService {
  /// Nomor build aplikasi ini (diisi otomatis saat build di GitHub Actions).
  static const buildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  /// rilis = APK resmi (branch main), uji = APK uji coba (branch uji).
  static const channel = String.fromEnvironment('UPDATE_CHANNEL', defaultValue: 'rilis');

  static String get versionName => buildNumber == 0 ? 'dev' : '1.0.$buildNumber';

  /// Dipasang di MaterialApp agar dialog update bisa tampil dari layar mana pun.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static bool _started = false;
  static bool _busy = false;
  static DateTime? _lastCheck;
  static Timer? _timer;

  /// Mulai memantau update (dipanggil sekali dari main).
  static void start() {
    if (kIsWeb || _started || buildNumber == 0) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_Lifecycle());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check(force: true));
  }

  static void stop() => _timer?.cancel();

  /// Cek versi terbaru (jeda minimal 2 menit antar pengecekan).
  /// Parameter [context] dipertahankan untuk kompatibilitas; dialog memakai navigatorKey.
  static Future<void> check([BuildContext? context]) => _check();

  static Future<void> _check({bool force = false}) async {
    if (kIsWeb || buildNumber == 0 || _busy) return;
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 2)) return;
    _lastCheck = now;
    try {
      // TL, Trainer & PIC membaca latest_sm.json (selalu terbaru).
      // PC membaca latest.json, yang hanya diperbarui untuk rilis khusus PC ([pc] di pesan commit).
      final file = (Session.current?.usesAdminHome ?? false) ? 'latest_sm.json' : 'latest.json';
      final uri = Uri.parse('${AppConfig.supabaseUrl}/storage/v1/object/public/apk/$channel/$file'
          '?t=${now.millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final code = (m['version_code'] as num?)?.toInt() ?? 0;
      final url = '${m['url'] ?? ''}';
      if (code <= buildNumber || url.isEmpty) return;
      final ctx = navigatorKey.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;
      _busy = true;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(
          versi: '${m['version_name'] ?? code}',
          catatan: '${m['catatan'] ?? ''}',
          url: url,
        ),
      );
    } catch (_) {
      // Tidak ada internet atau file belum ada: coba lagi pada pengecekan berikutnya.
    } finally {
      _busy = false;
    }
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) UpdateService.check();
  }
}

/// Dialog update: langsung mengunduh APK di dalam aplikasi, lalu membuka layar pasang.
class _UpdateDialog extends StatefulWidget {
  final String versi;
  final String catatan;
  final String url;
  const _UpdateDialog({required this.versi, required this.catatan, required this.url});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? _sub;
  int? _persen;
  String? _error;
  bool _memasang = false;

  @override
  void initState() {
    super.initState();
    _mulai();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _mulai() {
    setState(() {
      _error = null;
      _persen = 0;
      _memasang = false;
    });
    _sub?.cancel();
    try {
      _sub = OtaUpdate()
          .execute(widget.url, destinationFilename: 'DailyReportNKA-${widget.versi}.apk')
          .listen(
        (e) {
          if (!mounted) return;
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              setState(() => _persen = int.tryParse(e.value ?? '') ?? _persen);
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              setState(() => _memasang = true);
            case OtaStatus.ALREADY_RUNNING_ERROR:
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() => _error = 'Izin memasang aplikasi belum diberikan. Izinkan "Install aplikasi tidak dikenal" '
                  'untuk Daily Report NKA, lalu coba lagi.');
            default:
              setState(() => _error = 'Update gagal diunduh (${e.status.name}). Periksa internet lalu coba lagi.');
          }
        },
        onError: (Object e) {
          if (mounted) setState(() => _error = 'Update gagal: $e');
        },
      );
    } catch (e) {
      setState(() => _error = 'Update gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update, size: 36),
        title: Text('Update ke versi ${widget.versi}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Versi kamu: ${UpdateService.versionName}.'),
          if (widget.catatan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.catatan, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700))
          else if (_memasang)
            const Text('Unduhan selesai. Ketuk "Perbarui" / "Install" pada layar Android. '
                'Data dan login tetap aman.')
          else ...[
            Text('Mengunduh update... ${_persen ?? 0}%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_persen ?? 0) / 100),
          ],
        ]),
        actions: [
          if (_error != null) ...[
            TextButton(
              onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
              child: const Text('Unduh lewat browser'),
            ),
            FilledButton(onPressed: _mulai, child: const Text('Coba lagi')),
          ],
          if (_memasang || _error != null)
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }
}
