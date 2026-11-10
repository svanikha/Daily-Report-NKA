import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'session.dart';

/// Cek versi baru saat aplikasi dibuka.
/// GitHub Actions mengunggah APK terbaru + latest.json ke bucket publik "apk"
/// di Supabase. Jika versi di server lebih baru, tampil pesan "Update tersedia".
class UpdateService {
  /// Nomor build aplikasi ini (diisi otomatis saat build di GitHub Actions).
  static const buildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  /// rilis = APK resmi (branch main), uji = APK uji coba (branch uji).
  static const channel = String.fromEnvironment('UPDATE_CHANNEL', defaultValue: 'rilis');

  static String get versionName => buildNumber == 0 ? 'dev' : '1.0.$buildNumber';

  static bool _checked = false;

  static Future<void> check(BuildContext context) async {
    if (kIsWeb) return; // versi web selalu terbaru, tidak perlu APK
    if (_checked || buildNumber == 0) return;
    _checked = true;
    try {
      // TL, Trainer & PIC membaca latest_sm.json (selalu terbaru).
      // PC membaca latest.json, yang hanya diperbarui untuk rilis khusus PC.
      final file = (Session.current?.usesAdminHome ?? false) ? 'latest_sm.json' : 'latest.json';
      final uri = Uri.parse('${AppConfig.supabaseUrl}/storage/v1/object/public/apk/$channel/$file'
          '?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final code = (m['version_code'] as num?)?.toInt() ?? 0;
      final url = '${m['url'] ?? ''}';
      if (code <= buildNumber || url.isEmpty) return;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update, size: 36),
          title: const Text('Update tersedia'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Versi ${m['version_name'] ?? code} sudah tersedia. Versi kamu: $versionName.'),
            if ('${m['catatan'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${m['catatan']}', style: Theme.of(ctx).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            const Text('Ketuk Download, tunggu selesai, lalu buka file dan pilih Update. Data dan login tetap aman.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nanti')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Tidak ada internet atau file belum ada: diam saja, coba lagi saat aplikasi dibuka berikutnya.
    }
  }
}
