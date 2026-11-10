import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Target bulanan per toko (unit, value, fokus A7 Pro, fokus Reno 16, IoT).
/// Target TL = total target semua toko Erafone di areanya (termasuk Rajawali).
/// Trainer mengatur toko di areanya, PIC NKA semua toko, TL hanya melihat.
class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  DateTime _bulan = monthStart();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _stores = [];
  final Map<String, TextEditingController> _c = {}; // "storeId|jenis"

  bool get _bisaAtur => Session.current!.isPic || Session.current!.isTrainer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final me = Session.current!;
      final res = await Future.wait<dynamic>([
        db.from('stores').select('id,nama,area_id,areas(nama)').eq('aktif', true).order('area_id').order('id'),
        db.from('store_targets').select('store_id,jenis,nilai').eq('bulan', ymd(_bulan)),
      ]);
      _stores = asList(res[0]).where((s) => me.isPic || toNum(s['area_id']).toInt() == me.areaId).toList();
      final nilai = {
        for (final r in asList(res[1])) '${r['store_id']}|${r['jenis']}': toNum(r['nilai']),
      };
      for (final c in _c.values) {
        c.dispose();
      }
      _c.clear();
      for (final s in _stores) {
        for (final d in targetDefs) {
          final k = '${s['id']}|${d.jenis}';
          final v = nilai[k];
          _c[k] = TextEditingController(text: v == null || v == 0 ? '' : '${v.toInt()}');
        }
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  num _v(String k) => digitsOnly(_c[k]?.text ?? '');

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final rows = [
        for (final s in _stores)
          for (final d in targetDefs)
            {
              'store_id': s['id'],
              'bulan': ymd(_bulan),
              'jenis': d.jenis,
              'nilai': _v('${s['id']}|${d.jenis}'),
            }
      ];
      await Session.db.from('store_targets').upsert(rows, onConflict: 'store_id,bulan,jenis');
      if (mounted) showMsg(context, 'Target ${namaBulan(_bulan)} tersimpan');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _gantiBulan(int n) {
    _bulan = DateTime(_bulan.year, _bulan.month + n, 1);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final areaTotal = <String, Map<String, num>>{};
    for (final s in _stores) {
      final a = '${asMap(s['areas'])['nama'] ?? ''}';
      final m = areaTotal.putIfAbsent(a, () => {});
      for (final d in targetDefs) {
        m[d.jenis] = (m[d.jenis] ?? 0) + _v('${s['id']}|${d.jenis}');
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Target bulanan toko')),
      bottomNavigationBar: _loading || _error != null || !_bisaAtur
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: Text('Simpan target ${namaBulan(_bulan)}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Row(children: [
                    IconButton(onPressed: () => _gantiBulan(-1), icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: Text(namaBulan(_bulan), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(onPressed: () => _gantiBulan(1), icon: const Icon(Icons.chevron_right)),
                  ]),
                  const SectionHeader('Target TL (total toko di area)'),
                  for (final e in areaTotal.entries)
                    Card(
                      child: ListTile(
                        title: Text('Area ${e.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text([
                          for (final d in targetDefs)
                            '${d.label}: ${d.rupiah ? rupiah(e.value[d.jenis] ?? 0) : angka(e.value[d.jenis] ?? 0)}',
                        ].join('\n')),
                      ),
                    ),
                  const SectionHeader('Target per toko'),
                  if (!_bisaAtur) const InfoBanner('Target diatur oleh Trainer dan PIC NKA.'),
                  for (final s in _stores) _storeCard(s),
                ]),
    );
  }

  Widget _storeCard(Map<String, dynamic> s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${asMap(s['areas'])['nama'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in targetDefs)
              SizedBox(
                width: d.rupiah ? 200 : 140,
                child: TextField(
                  controller: _c['${s['id']}|${d.jenis}'],
                  enabled: _bisaAtur,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: d.label, isDense: true, prefixText: d.rupiah ? 'Rp ' : null),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
