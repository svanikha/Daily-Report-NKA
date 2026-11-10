import 'dart:async';

import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/notif_service.dart';
import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Bar waktu istirahat di beranda PC (di atas menu bawah).
/// Istirahat 1x sehari; Kembali ke Toko hanya dalam radius toko.
/// Pada hari offday/izin bar ini menampilkan info bahwa kewajiban nonaktif.
class BreakBar extends StatefulWidget {
  final Profile pc;
  const BreakBar({super.key, required this.pc});

  @override
  State<BreakBar> createState() => _BreakBarState();
}

class _BreakBarState extends State<BreakBar> with WidgetsBindingObserver {
  Map<String, dynamic>? _brk;
  String? _libur;
  bool _loaded = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = Session.db;
      final today = todayStr();
      final res = await Future.wait<dynamic>([
        db.from('breaks').select().eq('pc_id', widget.pc.id).eq('tanggal', today),
        db.from('pc_day_status').select('status').eq('pc_id', widget.pc.id).eq('tanggal', today),
      ]);
      final b = asList(res[0]);
      final l = asList(res[1]);
      _brk = b.isEmpty ? null : b.first;
      _libur = l.isEmpty ? null : '${l.first['status']}';
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _start() async {
    final durasi = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.free_breakfast_outlined),
        title: const Text('Pilih waktu istirahat'),
        content: const Text('Istirahat hanya bisa 1 kali dalam sehari. '
            'Jika melewati waktu yang dipilih, RBM dan Store Manager akan menerima peringatan.'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, 60), child: const Text('1 jam')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 180), child: const Text('3 jam')),
        ],
      ),
    );
    if (durasi == null) return;
    setState(() => _busy = true);
    try {
      final r = asMap(await Session.db.rpc('mulai_istirahat', params: {'p_durasi': durasi}));
      await NotifService.scheduleBreak(parseWib(r['mulai'] as String), durasiMenit: durasi);
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _back() async {
    setState(() => _busy = true);
    try {
      final loc = await LocationService.current();
      final radius = widget.pc.radiusM;
      final jarak = loc.jarakToko ?? 0;
      if (loc.jarakToko != null && jarak > radius) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.location_off, color: Colors.red),
              title: const Text('Belum di toko'),
              content: Text('Kamu masih ${angka(jarak)} m dari toko. '
                  'Tombol aktif setelah kamu berada dalam radius $radius m dari toko.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti'))],
            ),
          );
        }
      } else {
        await Session.db.rpc('kembali_ke_toko', params: {'p_jarak': jarak});
        await NotifService.cancelBreak();
        await _load();
        if (mounted) showMsg(context, 'Selamat bekerja kembali');
      }
    } on LocationException catch (e) {
      if (mounted) {
        final open = await confirmDialog(context, 'Lokasi tidak terbaca', e.message, yes: e.gpsOff ? 'Buka pengaturan' : 'OK');
        if (open && e.gpsOff) await LocationService.openSettings();
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    if (_libur != null) {
      return _bar(
        color: Colors.teal,
        icon: Icons.beach_access,
        text: 'Hari ini ${_libur == 'izin' ? 'izin' : 'offday'}: semua kewajiban aplikasi nonaktif.',
      );
    }

    final b = _brk;
    if (b == null) {
      final open = pcInputOpen();
      return _bar(
        color: scheme.primary,
        icon: Icons.free_breakfast_outlined,
        text: 'Istirahat 1x sehari: pilih 1 jam atau 3 jam',
        action: FilledButton.tonal(
          onPressed: (_busy || !open) ? null : _start,
          child: const Text('Mulai Istirahat'),
        ),
      );
    }

    final mulai = parseWib(b['mulai'] as String);
    final durasi = toNum(b['durasi_menit'] ?? 180).toInt();
    final label = durasi == 60 ? '1 jam' : '3 jam';
    if (b['selesai'] == null) {
      final menit = wibNow().difference(mulai).inMinutes;
      final lewat = menit >= durasi;
      return _bar(
        color: lewat ? Colors.red.shade700 : Colors.orange.shade800,
        icon: Icons.timer_outlined,
        text: 'Istirahat ${_durasi(menit)} dari $label (mulai ${_jam(mulai)})${lewat ? ' - lewat waktu!' : ''}',
        action: FilledButton(
          onPressed: _busy ? null : _back,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kembali ke Toko'),
        ),
      );
    }

    final selesai = parseWib(b['selesai'] as String);
    final menit = selesai.difference(mulai).inMinutes;
    final lupa = b['flag'] == 'tidak_klik_kembali';
    return _bar(
      color: lupa ? Colors.red.shade700 : Colors.green.shade700,
      icon: lupa ? Icons.error_outline : Icons.check_circle_outline,
      text: lupa
          ? 'Istirahat hari ini ditutup otomatis (tidak klik kembali)'
          : 'Istirahat selesai: ${_durasi(menit)} dari $label (${_jam(mulai)}-${_jam(selesai)})',
    );
  }

  String _jam(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
  String _durasi(int m) => m >= 60 ? '${m ~/ 60} jam ${m % 60} menit' : '$m menit';

  Widget _bar({required Color color, required IconData icon, required String text, Widget? action}) {
    return Material(
      color: color.withValues(alpha: 0.1),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
            if (action != null) action,
          ]),
        ),
      ),
    );
  }
}
