import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Penjualan kompetitor harian: jumlah unit per brand di toko yang sama.
/// Disimpan untuk semua brand (termasuk 0), jadi menyimpan semua 0 = "kompetitor nihil".
class KompetitorScreen extends StatefulWidget {
  final TokoHari toko;
  const KompetitorScreen({super.key, required this.toko});

  @override
  State<KompetitorScreen> createState() => _KompetitorScreenState();
}

class _KompetitorScreenState extends State<KompetitorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _brands = [];
  final Map<int, int> _unit = {};
  bool _terisi = false;
  num _oppo = 0;

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('competitor_brands').select('id,nama').eq('aktif', true).order('urutan'),
        db.from('competitor_sales').select('brand_id,unit').eq('store_id', t.storeId).eq('tanggal', t.tgl),
        db.from('sales').select('qty').eq('store_id', t.storeId).eq('tanggal', t.tgl).eq('tipe', 'HP'),
      ]);
      _brands = asList(res[0]);
      final rows = asList(res[1]);
      _terisi = rows.isNotEmpty;
      _unit
        ..clear()
        ..addAll({for (final r in rows) toNum(r['brand_id']).toInt(): toNum(r['unit']).toInt()});
      _oppo = asList(res[2]).fold<num>(0, (a, r) => a + toNum(r['qty']));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _total => _unit.values.fold(0, (a, b) => a + b);

  Future<void> _save() async {
    if (_total == 0) {
      final ok = await confirmDialog(context, 'Semua 0?', 'Simpan bahwa hari ini tidak ada penjualan kompetitor di toko ini?',
          yes: 'Simpan');
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      final me = Session.current!;
      await Session.db.from('competitor_sales').upsert([
        for (final b in _brands)
          {
            'store_id': t.storeId,
            'tanggal': t.tgl,
            'brand_id': b['id'],
            'unit': _unit[toNum(b['id']).toInt()] ?? 0,
            'diinput_oleh': me.id,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }
      ], onConflict: 'store_id,tanggal,brand_id');
      if (!mounted) return;
      showMsg(context, 'Data kompetitor tersimpan');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final semua = _oppo + _total;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Penjualan kompetitor'),
          Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      bottomNavigationBar: _loading || _error != null || !boleh
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: const Text('Simpan data kompetitor'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                  if (_terisi) const InfoBanner('Sudah diisi. Ubah angka lalu simpan lagi jika ada koreksi.', icon: Icons.check_circle),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(child: _kpi('OPPO (HP)', angka(_oppo))),
                        Expanded(child: _kpi('Kompetitor', angka(_total))),
                        Expanded(child: _kpi('Market share', semua > 0 ? '${(_oppo / semua * 100).toStringAsFixed(0)}%' : '-')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Isi jumlah unit HP yang terjual per brand di toko ini hari ini.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final b in _brands) _row(b, boleh),
                ]),
    );
  }

  Widget _kpi(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _row(Map<String, dynamic> b, bool boleh) {
    final id = toNum(b['id']).toInt();
    final v = _unit[id] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
        child: Row(children: [
          Expanded(child: Text('${b['nama']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(
            onPressed: boleh && v > 0 ? () => setState(() => _unit[id] = v - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 40,
            child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: boleh ? () => setState(() => _unit[id] = v + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      ),
    );
  }
}
