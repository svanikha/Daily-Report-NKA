import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/pengingat_pc.dart';
import '../../widgets/widgets.dart';
import '../riwayat_screens.dart';
import '../toko/hari_toko_view.dart';

/// Detail satu toko untuk TL / Trainer / PIC: sama dengan beranda PC, tanggal bisa dipilih.
class TokoDetailScreen extends StatefulWidget {
  final TokoHari toko;
  const TokoDetailScreen({super.key, required this.toko});

  @override
  State<TokoDetailScreen> createState() => _TokoDetailScreenState();
}

class _TokoDetailScreenState extends State<TokoDetailScreen> {
  final _view = GlobalKey<HariTokoViewState>();
  late TokoHari _toko = widget.toko;
  bool _busy = false;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toko.tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      helpText: 'Tanggal laporan',
    );
    if (d == null) return;
    setState(() => _toko = TokoHari(
          storeId: _toko.storeId,
          toko: _toko.toko,
          area: _toko.area,
          pcId: _toko.pcId,
          pcNama: _toko.pcNama,
          punyaPc: _toko.punyaPc,
          tanggal: dateOnly(d),
        ));
  }

  /// Reset semua laporan toko pada tanggal terpilih (jika PC salah input): semua kembali 0.
  Future<void> _reset() async {
    final tgl = hariTgl(_toko.tanggal);
    final ok = await confirmDialog(
      context,
      'Reset laporan $tgl?',
      'SEMUA data ${_toko.toko} tanggal ini dihapus dan kembali 0:\n'
          '• stok\n• penjualan HP & IoT (termasuk NOSELL)\n• MS Allbrand\n• cek display + foto\n'
          '• activity sosmed & cek limit leasing\n• laporan terkirim\n\n'
          'Data istirahat tidak ikut dihapus. Tindakan ini tidak bisa dibatalkan.',
      yes: 'Lanjut',
    );
    if (!ok || !mounted) return;
    final yakin = await confirmDialog(context, 'Yakin reset?',
        'Data ${_toko.toko} $tgl akan hilang permanen dan PC harus mengisi ulang.', yes: 'Ya, reset');
    if (!yakin) return;
    setState(() => _busy = true);
    try {
      final r = asMap(await Session.db.rpc('reset_laporan', params: {'p_store': _toko.storeId, 'p_tanggal': _toko.tgl}));
      if (mounted) {
        showMsg(context, 'Laporan $tgl direset (${r['penjualan_dihapus'] ?? 0} penjualan dihapus). PC diberi pengingat.');
      }
      await _view.currentState?.load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_toko.toko),
          Text('${_toko.punyaPc ? 'PC: ${_toko.pcNama ?? '-'}' : 'Non PC'} · ${tglPendek(_toko.tanggal)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          if (_toko.punyaPc && _toko.pcId != null)
            IconButton(
              onPressed: () => showKirimPengingat(context, storeId: _toko.storeId, toko: _toko.toko, pcNama: _toko.pcNama),
              icon: const Icon(Icons.notifications_active),
              tooltip: 'Ingatkan PC',
            ),
          IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal'),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (v) {
              if (v == 'muat') _view.currentState?.load();
              if (v == 'reset') _reset();
              if (v == 'istirahat') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RiwayatIstirahatScreen(storeId: _toko.storeId, judul: _toko.toko)));
              }
              if (v == 'cek') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RiwayatCekLimitScreen(storeId: _toko.storeId, judul: _toko.toko)));
              }
              if (v == 'galeri') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => GaleriFotoScreen(storeId: _toko.storeId)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'muat', child: ListTile(leading: Icon(Icons.refresh), title: Text('Muat ulang'))),
              const PopupMenuItem(
                  value: 'istirahat', child: ListTile(leading: Icon(Icons.free_breakfast), title: Text('Riwayat istirahat'))),
              const PopupMenuItem(value: 'cek', child: ListTile(leading: Icon(Icons.fact_check), title: Text('Riwayat cek limit'))),
              const PopupMenuItem(value: 'galeri', child: ListTile(leading: Icon(Icons.photo_library), title: Text('Galeri foto'))),
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  leading: Icon(Icons.restart_alt, color: Colors.red.shade700),
                  title: Text('Reset laporan tanggal ini', style: TextStyle(color: Colors.red.shade700)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: HariTokoView(key: _view, toko: _toko)),
      ]),
    );
  }
}
