import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/status_online.dart';
import '../../widgets/widgets.dart';

String ukuranTeks(num b) {
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(2)} GB';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}

const _namaBucket = {'bukti': 'Foto bukti PC', 'apk': 'File update aplikasi (APK)', 'profil': 'Foto profil'};

/// Penyimpanan server (khusus PIC NKA / Manajer Trainer): pemakaian, aturan hapus otomatis,
/// riwayat pembersihan, dan tombol bersihkan sekarang.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _r;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Session.db.rpc('info_storage'));
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errMsg(e));
    }
  }

  Future<void> _bersihkan() async {
    final ok = await confirmDialog(
      context,
      'Bersihkan sekarang?',
      'Foto bukti yang lebih tua dari ${_r?['umur_hari'] ?? 30} hari dan APK lama akan dihapus permanen. '
          'Foto profil tidak dihapus.',
      yes: 'Bersihkan',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Session.db.rpc('jalankan_bersihkan', params: {'p_pemicu': 'manual'});
      if (mounted) showMsg(context, 'Pembersihan berjalan di server, tunggu ±20 detik');
      await Future<void>.delayed(const Duration(seconds: 20));
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Penyimpanan server')),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _bersihkan,
                  icon: busyIcon(_busy, Icons.cleaning_services),
                  label: const Text('Bersihkan sekarang'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _error != null
          ? ErrorRetry(error: _error!, onRetry: _load)
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _isi(r)),
    );
  }

  Widget _isi(Map<String, dynamic> r) {
    final total = toNum(r['total']);
    final kuota = toNum(r['kuota']);
    final p = kuota > 0 ? total / kuota * 100 : 0.0;
    final batas = toNum(r['batas_persen']);
    final c = p >= batas ? Colors.red.shade700 : (p >= batas - 20 ? Colors.orange.shade800 : Colors.green.shade700);
    final perBucket = asMap(r['per_bucket']);
    final log = asList(r['log']);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Terpakai', style: TextStyle(fontWeight: FontWeight.bold))),
              Text('${p.toStringAsFixed(0)}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (p / 100).clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                color: c,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 6),
            Text('${ukuranTeks(total)} dari ${ukuranTeks(kuota)}', style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 20),
            for (final e in perBucket.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(_namaBucket[e.key] ?? e.key)),
                  Text(ukuranTeks(toNum(e.value)), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ),
      InfoBanner(
        'Hapus otomatis setiap hari pukul 02.00 WIB:\n'
        '• Foto bukti PC lebih tua dari ${r['umur_hari']} hari\n'
        '• APK lama (5 versi terbaru disimpan)\n'
        '• Jika masih ≥ $batas% kuota: foto tertua ikut dihapus sampai di bawah 70% (foto 7 hari terakhir aman)\n'
        'Foto profil tidak pernah dihapus.',
        icon: Icons.auto_delete,
      ),
      const SectionHeader('Riwayat pembersihan'),
      if (log.isEmpty) const EmptyState(icon: Icons.history, text: 'Belum pernah dibersihkan'),
      for (final l in log)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: Icon(l['pemicu'] == 'manual' ? Icons.touch_app : Icons.schedule),
            title: Text('${waktuSingkat(parseWib('${l['waktu']}'))} · ${l['pemicu'] == 'manual' ? 'manual' : 'otomatis'}'),
            subtitle: Text(
              '${l['foto_dihapus']} foto · ${l['apk_dihapus']} APK · dibebaskan ${ukuranTeks(toNum(l['bytes_dibebaskan']))}\n'
              '${ukuranTeks(toNum(l['ukuran_sebelum']))} → ${ukuranTeks(toNum(l['ukuran_sesudah']))}'
              '${l['catatan'] != null ? '\n${l['catatan']}' : ''}',
            ),
          ),
        ),
    ]);
  }
}
