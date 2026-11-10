import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Satu baris rincian: tipe HP kompetitor + jumlah unit.
class _Entry {
  final TextEditingController tipe;
  int unit;
  _Entry(String t, this.unit) : tipe = TextEditingController(text: t);
}

/// MS Allbrand: penjualan HP semua brand kompetitor di toko yang sama, per brand,
/// per segmen harga (< 3 jt, 3-6 jt, 6 jt up), lengkap dengan tipe dan unitnya.
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

  /// brandId -> segmen -> daftar tipe
  final Map<int, Map<String, List<_Entry>>> _data = {};

  /// Unit HP OPPO hari ini per segmen (dari harga jual).
  final Map<String, num> _oppo = {for (final s in segmenList) s: 0};

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposeEntries();
    super.dispose();
  }

  void _disposeEntries() {
    for (final b in _data.values) {
      for (final l in b.values) {
        for (final e in l) {
          e.tipe.dispose();
        }
      }
    }
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
        db
            .from('competitor_sales_detail')
            .select('brand_id,segmen,tipe,unit')
            .eq('store_id', t.storeId)
            .eq('tanggal', t.tgl)
            .order('created_at'),
        db.from('competitor_sales').select('brand_id').eq('store_id', t.storeId).eq('tanggal', t.tgl).limit(1),
        db.from('sales').select('qty,harga').eq('store_id', t.storeId).eq('tanggal', t.tgl).eq('tipe', 'HP'),
      ]);
      _brands = asList(res[0]);
      _disposeEntries();
      _data.clear();
      for (final b in _brands) {
        _data[toNum(b['id']).toInt()] = {for (final s in segmenList) s: <_Entry>[]};
      }
      for (final d in asList(res[1])) {
        final m = _data[toNum(d['brand_id']).toInt()];
        m?['${d['segmen']}']?.add(_Entry('${d['tipe']}', toNum(d['unit']).toInt()));
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

  int _sumSeg(int brand, String seg) => (_data[brand]?[seg] ?? const <_Entry>[]).fold(0, (a, e) => a + e.unit);
  int _sumBrand(int brand) => segmenList.fold(0, (a, s) => a + _sumSeg(brand, s));
  int _sumSegAll(String seg) => _data.keys.fold(0, (a, b) => a + _sumSeg(b, seg));
  int get _total => _data.keys.fold(0, (a, b) => a + _sumBrand(b));

  Future<void> _save() async {
    final detail = <Map<String, dynamic>>[];
    for (final b in _brands) {
      final id = toNum(b['id']).toInt();
      for (final s in segmenList) {
        for (final e in _data[id]![s]!) {
          if (e.unit <= 0) continue;
          if (e.tipe.text.trim().isEmpty) {
            showMsg(context, 'Isi tipe HP untuk ${b['nama']} ${segmenLabel[s]}');
            return;
          }
          detail.add({'brand_id': id, 'segmen': s, 'tipe': e.tipe.text.trim(), 'unit': e.unit});
        }
      }
    }
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
                              Expanded(child: Text('OPPO ${angka(_oppo[s] ?? 0)} · lain ${angka(_sumSegAll(s))}')),
                              Text(_ms(_oppo[s] ?? 0, _sumSegAll(s)), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Ketuk brand, isi jumlah unit per segmen harga beserta tipenya. '
                      'Contoh vivo 3 jt - 6 jt: Y11d Pro 4/128 = 2 unit.',
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
    final total = _sumBrand(id);
    final ringkas = [
      for (final s in segmenList)
        if (_sumSeg(id, s) > 0) '${segmenLabel[s]}: ${_sumSeg(id, s)}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        key: PageStorageKey('brand-$id'),
        title: Text('${b['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(ringkas.isEmpty ? 'Belum ada' : ringkas),
        trailing: Text('$total unit',
            style: TextStyle(fontWeight: FontWeight.bold, color: total > 0 ? Theme.of(context).colorScheme.primary : Colors.grey)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [for (final s in segmenList) _segmen(id, s, boleh)],
      ),
    );
  }

  Widget _segmen(int brand, String seg, bool boleh) {
    final list = _data[brand]![seg]!;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(segmenLabel[seg]!, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${_sumSeg(brand, seg)} unit', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        for (var i = 0; i < list.length; i++)
          Row(children: [
            Expanded(
              child: TextField(
                controller: list[i].tipe,
                enabled: boleh,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(isDense: true, hintText: 'Tipe, misal Y11d Pro 4/128'),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: boleh && list[i].unit > 1 ? () => setState(() => list[i].unit--) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(width: 26, child: Text('${list[i].unit}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: boleh ? () => setState(() => list[i].unit++) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Hapus',
              onPressed: boleh
                  ? () => setState(() {
                        list[i].tipe.dispose();
                        list.removeAt(i);
                      })
                  : null,
              icon: const Icon(Icons.close),
            ),
          ]),
        if (boleh)
          TextButton.icon(
            onPressed: () => setState(() => list.add(_Entry('', 1))),
            icon: const Icon(Icons.add),
            label: const Text('Tambah tipe'),
          ),
      ]),
    );
  }
}
