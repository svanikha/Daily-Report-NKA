import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// MS Allbrand: penjualan HP semua brand lain di toko yang sama, per brand dan
/// per segmen harga (< 3 jt, 3-6 jt, 6 jt up). Cukup angka unit, tanpa tipe.
class MsAllbrandScreen extends StatefulWidget {
  final TokoHari toko;
  const MsAllbrandScreen({super.key, required this.toko});

  @override
  State<MsAllbrandScreen> createState() => _MsAllbrandScreenState();
}

class _MsAllbrandScreenState extends State<MsAllbrandScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _terisi = false;
  List<Map<String, dynamic>> _brands = [];

  /// brandId -> segmen -> unit
  final Map<int, Map<String, int>> _unit = {};

  /// Unit HP OPPO hari ini per segmen (dari harga jual).
  final Map<String, num> _oppo = {for (final s in segmenList) s: 0};

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _segmenDariHarga(num harga) => harga < 3000000 ? 'lt3' : (harga < 6000000 ? '3to6' : 'gt6');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('competitor_brands').select('id,nama').eq('aktif', true).order('urutan'),
        db.from('competitor_sales_detail').select('brand_id,segmen,unit').eq('store_id', t.storeId).eq('tanggal', t.tgl),
        db.from('competitor_sales').select('brand_id').eq('store_id', t.storeId).eq('tanggal', t.tgl).limit(1),
        db.from('sales').select('qty,harga').eq('store_id', t.storeId).eq('tanggal', t.tgl).eq('tipe', 'HP'),
      ]);
      _brands = asList(res[0]);
      _unit.clear();
      for (final b in _brands) {
        _unit[toNum(b['id']).toInt()] = {for (final s in segmenList) s: 0};
      }
      for (final d in asList(res[1])) {
        final m = _unit[toNum(d['brand_id']).toInt()];
        final s = '${d['segmen']}';
        if (m != null && m.containsKey(s)) m[s] = m[s]! + toNum(d['unit']).toInt();
      }
      _terisi = asList(res[2]).isNotEmpty;
      for (final s in segmenList) {
        _oppo[s] = 0;
      }
      for (final r in asList(res[3])) {
        final s = _segmenDariHarga(toNum(r['harga']));
        _oppo[s] = (_oppo[s] ?? 0) + toNum(r['qty']);
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _sumBrand(int brand) => (_unit[brand]?.values ?? const <int>[]).fold(0, (a, b) => a + b);
  int _sumSeg(String seg) => _unit.values.fold(0, (a, m) => a + (m[seg] ?? 0));
  int get _total => _unit.keys.fold(0, (a, b) => a + _sumBrand(b));

  void _set(int brand, String seg, int v) => setState(() => _unit[brand]![seg] = v < 0 ? 0 : v);

  Future<void> _ketik(int brand, String seg, String namaBrand) async {
    final c = TextEditingController(text: '${_unit[brand]![seg]}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$namaBrand · ${segmenLabel[seg]}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Jumlah unit', suffixText: 'unit'),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    if (v != null) _set(brand, seg, v);
  }

  Future<void> _save() async {
    final detail = <Map<String, dynamic>>[
      for (final e in _unit.entries)
        for (final s in segmenList)
          if ((e.value[s] ?? 0) > 0) {'brand_id': e.key, 'segmen': s, 'unit': e.value[s]},
    ];
    if (detail.isEmpty) {
      final ok = await confirmDialog(context, 'Semua brand 0?',
          'Simpan bahwa hari ini tidak ada penjualan brand lain di toko ini?', yes: 'Simpan');
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await Session.db.rpc('simpan_ms_allbrand', params: {'p_store': t.storeId, 'p_tanggal': t.tgl, 'p_detail': detail});
      if (!mounted) return;
      showMsg(context, 'MS Allbrand tersimpan');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  String _ms(num oppo, num lain) => oppo + lain > 0 ? '${(oppo / (oppo + lain) * 100).toStringAsFixed(0)}%' : '-';

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final oppoTotal = _oppo.values.fold<num>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MS Allbrand'),
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
                  label: const Text('Simpan MS Allbrand'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                  if (_terisi) const InfoBanner('Sudah diisi. Ubah lalu simpan lagi jika ada koreksi.', icon: Icons.check_circle),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: _kpi('OPPO', angka(oppoTotal))),
                          Expanded(child: _kpi('Brand lain', angka(_total))),
                          Expanded(child: _kpi('MS OPPO', _ms(oppoTotal, _total))),
                        ]),
                        const Divider(),
                        for (final s in segmenList)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              SizedBox(width: 90, child: Text(segmenLabel[s]!, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Expanded(child: Text('OPPO ${angka(_oppo[s] ?? 0)} · lain ${angka(_sumSeg(s))}')),
                              Text(_ms(_oppo[s] ?? 0, _sumSeg(s)), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Isi jumlah unit HP yang terjual per brand dan segmen harga di toko ini. Ketuk angka untuk mengetik.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final b in _brands) _brandCard(b, boleh),
                ]),
    );
  }

  Widget _kpi(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _brandCard(Map<String, dynamic> b, bool boleh) {
    final id = toNum(b['id']).toInt();
    final nama = '${b['nama']}';
    final total = _sumBrand(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('$total unit',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: total > 0 ? Theme.of(context).colorScheme.primary : Colors.grey)),
            ),
          ]),
          for (final s in segmenList)
            Row(children: [
              Expanded(child: Text(segmenLabel[s]!)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh && (_unit[id]![s] ?? 0) > 0 ? () => _set(id, s, _unit[id]![s]! - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              InkWell(
                onTap: boleh ? () => _ketik(id, s, nama) : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text('${_unit[id]![s]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh ? () => _set(id, s, (_unit[id]![s] ?? 0) + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
        ]),
      ),
    );
  }
}
