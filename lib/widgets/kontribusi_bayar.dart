import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Kontribusi penjualan HP & IoT bulan berjalan menurut pembayaran:
/// Cash vs Kredit, lalu rincian Kredit per leasing (unit, value, persen).
/// [storeId] null = semua toko di cakupan akun.
class KontribusiBayar extends StatefulWidget {
  final DateTime tanggal;
  final int? storeId;
  const KontribusiBayar({super.key, required this.tanggal, this.storeId});

  @override
  State<KontribusiBayar> createState() => _KontribusiBayarState();
}

class _KontribusiBayarState extends State<KontribusiBayar> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _tipe = 'HP';
  bool _pakaiValue = false; // false = unit, true = value

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KontribusiBayar old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId || !isSameDay(monthStart(old.tanggal), monthStart(widget.tanggal)) ||
        old.tanggal != widget.tanggal) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      _rows = asList(await Session.db.rpc('kontribusi_bayar', params: {
        'p_dari': ymd(monthStart(widget.tanggal)),
        'p_sampai': ymd(widget.tanggal),
        'p_store': widget.storeId,
      }));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  num _v(Map<String, dynamic> r) => toNum(_pakaiValue ? r['value'] : r['unit']);
  String _fmt(num v) => _pakaiValue ? rupiah(v) : '${angka(v)} unit';

  @override
  Widget build(BuildContext context) {
    final rows = _rows.where((r) => r['tipe'] == _tipe).toList();
    final total = rows.fold<num>(0, (a, r) => a + _v(r));
    num metode(String m) => rows.where((r) => r['metode'] == m).fold<num>(0, (a, r) => a + _v(r));
    final cash = metode('Cash');
    final kredit = metode('Kredit');
    final tanpa = metode('-');
    final perLeasing = <String, num>{};
    for (final r in rows.where((r) => r['metode'] == 'Kredit')) {
      perLeasing['${r['cara_bayar']}'] = (perLeasing['${r['cara_bayar']}'] ?? 0) + _v(r);
    }
    final leasing = perLeasing.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final perCash = <String, num>{};
    for (final r in rows.where((r) => r['metode'] == 'Cash')) {
      perCash['${r['cara_bayar']}'] = (perCash['${r['cara_bayar']}'] ?? 0) + _v(r);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Kontribusi pembayaran · ${namaBulan(widget.tanggal)} (s.d. ${widget.tanggal.day})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'HP', label: Text('HP')),
                  ButtonSegment(value: 'IOT', label: Text('IoT')),
                ],
                selected: {_tipe},
                onSelectionChanged: (s) => setState(() => _tipe = s.first),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Unit')),
                  ButtonSegment(value: true, label: Text('Value')),
                ],
                selected: {_pakaiValue},
                onSelectionChanged: (s) => setState(() => _pakaiValue = s.first),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!)
          else if (total <= 0)
            const Padding(padding: EdgeInsets.all(8), child: Text('Belum ada penjualan bulan ini', textAlign: TextAlign.center))
          else ...[
            _bar('Cash', cash, total, Colors.green.shade700),
            for (final e in perCash.entries) _sub(e.key == '-' ? 'Tanpa detail' : e.key, e.value, total),
            _bar('Kredit', kredit, total, Colors.indigo),
            for (final e in leasing) _sub(e.key, e.value, total, dariKredit: kredit),
            if (tanpa > 0) _bar('Tanpa keterangan', tanpa, total, Colors.grey),
            const Divider(),
            Text('Total ${_tipe == 'HP' ? 'HP' : 'IoT'}: ${_fmt(total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  Widget _bar(String label, num v, num total, Color c) {
    final p = total > 0 ? v / total * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Text('${_fmt(v)} · ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${p.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, color: c)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: (p / 100).clamp(0.0, 1.0).toDouble(), minHeight: 8, color: c,
              backgroundColor: Colors.grey.shade200),
        ),
      ]),
    );
  }

  /// Rincian (leasing / cara bayar cash). Untuk leasing ditampilkan juga persen dari total Kredit.
  Widget _sub(String label, num v, num total, {num? dariKredit}) {
    final p = total > 0 ? v / total * 100 : 0.0;
    final pk = dariKredit != null && dariKredit > 0 ? v / dariKredit * 100 : null;
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 2),
      child: Row(children: [
        Expanded(child: Text('• $label', style: const TextStyle(fontSize: 13))),
        Text(_fmt(v), style: const TextStyle(fontSize: 13)),
        SizedBox(
          width: 96,
          child: Text(
            pk == null ? '${p.toStringAsFixed(0)}%' : '${pk.toStringAsFixed(0)}% kredit',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ]),
    );
  }
}
