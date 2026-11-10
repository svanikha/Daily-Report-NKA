import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Rupiah ringkas untuk kotak kalender: 850rb, 12,5jt, 1,2M.
String rpRingkas(num v) {
  if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1).replaceAll('.', ',')}M';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '')}jt';
  if (v >= 1000) return '${(v / 1000).round()}rb';
  return '${v.round()}';
}

/// Kalender penjualan bulanan (TL, Trainer, PIC): unit & value HP per hari untuk semua toko
/// di cakupan akun, atau satu toko yang dipilih. Ketuk tanggal untuk melihat laporan hari itu.
class KalenderPenjualan extends StatefulWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  /// Daftar toko untuk filter: {store_id, toko}.
  final List<Map<String, dynamic>> toko;
  const KalenderPenjualan({super.key, required this.selected, required this.onSelect, required this.toko});

  @override
  State<KalenderPenjualan> createState() => _KalenderPenjualanState();
}

class _KalenderPenjualanState extends State<KalenderPenjualan> {
  late DateTime _bulan = monthStart(widget.selected);
  int? _store;
  bool _loading = true;
  String? _error;
  final Map<String, Map<String, dynamic>> _hari = {};

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
      final rows = asList(await Session.db.rpc('kalender_penjualan', params: {'p_bulan': ymd(_bulan), 'p_store': _store}));
      _hari
        ..clear()
        ..addAll({for (final r in rows) '${r['tanggal']}': r});
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _ganti(int n) {
    final b = DateTime(_bulan.year, _bulan.month + n, 1);
    if (b.isAfter(monthStart(wibToday()))) return;
    _bulan = b;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = wibToday();
    final first = _bulan;
    final last = monthEnd(_bulan);
    final lead = first.weekday - 1; // Senin = kolom pertama
    final maxUnit = _hari.values.fold<num>(0, (a, r) => toNum(r['unit']) > a ? toNum(r['unit']) : a);
    final totUnit = _hari.values.fold<num>(0, (a, r) => a + toNum(r['unit']));
    final totValue = _hari.values.fold<num>(0, (a, r) => a + toNum(r['value']));
    final totIot = _hari.values.fold<num>(0, (a, r) => a + toNum(r['iot']));
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(onPressed: () => _ganti(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('Kalender penjualan · ${namaBulan(_bulan)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: isSameDay(_bulan, monthStart(today)) ? null : () => _ganti(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          if (widget.toko.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonFormField<int?>(
                initialValue: _store,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Toko'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Semua toko')),
                  for (final t in widget.toko)
                    DropdownMenuItem<int?>(value: toNum(t['store_id']).toInt(), child: Text('${t['toko']}')),
                ],
                onChanged: (v) {
                  _store = v;
                  _load();
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            for (final h in const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'])
              Expanded(child: Text(h, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center))
          else
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.82,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                for (var d = 1; d <= last.day; d++) _cell(DateTime(_bulan.year, _bulan.month, d), today, maxUnit, primary),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Total ${namaBulan(_bulan)}: HP ${angka(totUnit)} unit · ${rupiah(totValue)} · IoT ${angka(totIot)} unit',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }

  Widget _cell(DateTime d, DateTime today, num maxUnit, Color primary) {
    final r = _hari[ymd(d)];
    final unit = toNum(r?['unit']);
    final value = toNum(r?['value']);
    final future = d.isAfter(today);
    final sel = isSameDay(d, widget.selected);
    final kuat = maxUnit > 0 ? (unit / maxUnit).clamp(0.0, 1.0).toDouble() : 0.0;
    final bg = future ? Colors.grey.shade100 : (unit > 0 ? primary.withValues(alpha: 0.12 + 0.55 * kuat) : Colors.red.shade50);
    final fg = kuat > 0.6 ? Colors.white : Colors.black87;
    return InkWell(
      onTap: future ? null : () => widget.onSelect(d),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: sel ? Border.all(color: Colors.black87, width: 2) : null,
        ),
        padding: const EdgeInsets.all(2),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.day}', style: TextStyle(fontSize: 10, color: future ? Colors.grey : fg)),
          if (!future) ...[
            Text('$unit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: fg)),
            Text(value > 0 ? rpRingkas(value) : '-', style: TextStyle(fontSize: 8.5, color: fg), maxLines: 1),
          ],
        ]),
      ),
    );
  }
}
