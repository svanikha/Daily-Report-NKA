import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/notif_service.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';

/// Istirahat PC (hanya jika keluar toko): pilih 1 jam / 2 jam, wajib selfie di area toko
/// saat mulai dan saat kembali. Lokasi divalidasi lagi di server.
class IstirahatCard extends StatefulWidget {
  final Map<String, dynamic>? istirahat; // baris breaks hari ini
  final String toko;
  final VoidCallback onChanged;
  const IstirahatCard({super.key, required this.istirahat, required this.toko, required this.onChanged});

  @override
  State<IstirahatCard> createState() => _IstirahatCardState();
}

class _IstirahatCardState extends State<IstirahatCard> {
  bool _busy = false;
  Timer? _tick;

  Map<String, dynamic>? get b => widget.istirahat;
  bool get _berjalan => b != null && b!['selesai'] == null;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _berjalan) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Ambil selfie dari kamera depan, cek GPS, lalu unggah. Mengembalikan (path, lat, lng).
  Future<(String, double, double)?> _selfie(String label) async {
    final p = await PhotoService.pick(context, selfie: true, label: label, cameraOnly: true, toko: widget.toko);
    if (p == null) return null;
    if (p.lat == null || p.lng == null) {
      throw 'Lokasi tidak terbaca. Nyalakan GPS lalu ulangi selfie.';
    }
    final path = await PhotoService.upload(Session.current!.storeId!, 'breaks', p.bytes);
    return (path, p.lat!, p.lng!);
  }

  Future<void> _mulai(int menit) async {
    final label = menit == 60 ? '1 jam' : '2 jam';
    final ok = await confirmDialog(
      context,
      'Mulai istirahat $label?',
      'Ambil selfie di area toko sekarang. Saat kembali, kamu wajib selfie lagi di area toko.',
      yes: 'Selfie & mulai',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final s = await _selfie('Mulai istirahat $label');
      if (s != null) {
        final r = asMap(await Session.db.rpc('mulai_istirahat', params: {
          'p_durasi': menit,
          'p_path': s.$1,
          'p_lat': s.$2,
          'p_lng': s.$3,
        }));
        await NotifService.scheduleBreak(parseWib('${r['mulai']}'), durasiMenit: menit);
        if (mounted) showMsg(context, 'Istirahat $label dimulai');
        widget.onChanged();
      }
    } on PhotoRejected catch (e) {
      if (mounted) await showRejected(context, e.message);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _kembali() async {
    setState(() => _busy = true);
    try {
      final s = await _selfie('Kembali ke toko');
      if (s != null) {
        await Session.db.rpc('kembali_ke_toko', params: {'p_path': s.$1, 'p_lat': s.$2, 'p_lng': s.$3});
        await NotifService.cancelBreak();
        if (mounted) showMsg(context, 'Selamat bekerja kembali');
        widget.onChanged();
      }
    } on PhotoRejected catch (e) {
      if (mounted) await showRejected(context, e.message);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (b == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.free_breakfast),
              const SizedBox(width: 8),
              Text('Istirahat', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text('Hanya jika keluar toko. Selfie wajib di area toko saat mulai dan kembali. Maksimal 1x sehari.',
                style: t.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || lewatBatasLaporan() ? null : () => _mulai(60),
                  icon: busyIcon(false, Icons.camera_front),
                  label: const Text('1 jam'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || lewatBatasLaporan() ? null : () => _mulai(120),
                  icon: const Icon(Icons.camera_front),
                  label: const Text('2 jam'),
                ),
              ),
            ]),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          ]),
        ),
      );
    }

    final mulai = parseWib('${b!['mulai']}');
    final durasi = toNum(b!['durasi_menit']).toInt();
    final label = durasi == 60 ? '1 jam' : '2 jam';
    if (_berjalan) {
      final batas = mulai.add(Duration(minutes: durasi));
      final sisa = batas.difference(wibNow()).inMinutes;
      final lewat = sisa < 0;
      return Card(
        color: lewat ? Colors.red.shade50 : Colors.amber.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.timer, color: lewat ? Colors.red.shade700 : Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Sedang istirahat $label', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Mulai ${jamMenit(mulai)} · batas kembali ${jamMenit(batas)}'),
            Text(
              lewat ? 'TERLAMBAT ${-sisa} menit' : 'Sisa $sisa menit',
              style: TextStyle(fontWeight: FontWeight.bold, color: lewat ? Colors.red.shade700 : Colors.black87),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _kembali,
              icon: busyIcon(_busy, Icons.camera_front),
              label: const Text('Selfie kembali ke toko'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ]),
        ),
      );
    }

    final selesai = parseWib('${b!['selesai']}');
    final telat = toNum(b!['terlambat_menit']).toInt();
    return Card(
      child: ListTile(
        leading: Icon(Icons.free_breakfast, color: telat > 0 ? Colors.red.shade700 : Colors.green.shade700),
        title: Text('Istirahat $label: ${jamMenit(mulai)} - ${jamMenit(selesai)}'),
        subtitle: Text(telat > 0 ? 'Terlambat $telat menit' : 'Tepat waktu'),
      ),
    );
  }
}
