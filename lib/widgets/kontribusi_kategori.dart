import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';

const _urutan = ['Walk-in', 'Databased', 'Online', 'Belum diisi'];
const _warna = {
  'Walk-in': Color(0xFF2E7D32),
  'Databased': Color(0xFF1565C0),
  'Online': Color(0xFF6A1B9A),
  'Belum diisi': Color(0xFF9E9E9E),
};
const _ikon = {
  'Walk-in': Icons.directions_walk,
  'Databased': Icons.contacts,
  'Online': Icons.language,
  'Belum diisi': Icons.help_outline,
};

/// Kontribusi kategori user (Walk-in / Databased / Online) bulan berjalan: unit, persentase, value.
/// storeId null = semua toko di cakupan akun.
class KontribusiKategori extends StatefulWidget {
  final int? storeId;
  final DateTime tanggal;
  const KontribusiKategori({super.key, required this.storeId, required this.tanggal});

  @override
  State<KontribusiKategori> createState() => _KontribusiKategoriState();
}

class _KontribusiKategoriState extends State<KontribusiKategori> {
  List<Map<String, dynamic>>? _rows;
  bool _iot = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KontribusiKategori old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId || !isSameDay(old.tanggal, widget.tanggal)) _load();
  }

  Future<void> _load() async {
    try {
      final r = asList(await Session.db
          .rpc('kontribusi_kategori', params: {'p_store': widget.storeId, 'p_tanggal': ymd(widget.tanggal)}));
      if (mounted) setState(() => _rows = r);
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    final list = rows.where((r) => (r['tipe'] == 'IOT') == _iot).toList();
    final total = list.fold<num>(0, (a, r) => a + toNum(r['unit']));
    num unit(String k) => list.where((r) => r['kategori'] == k).fold<num>(0, (a, r) => a + toNum(r['unit']));
    num value(String k) => list.where((r) => r['kategori'] == k).fold<num>(0, (a, r) => a + toNum(r['value']));
    num hari(String k) => list.where((r) => r['kategori'] == k).fold<num>(0, (a, r) => a + toNum(r['unit_hari']));
    final kategori = _urutan.where((k) => k != 'Belum diisi' || unit(k) > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.groups, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('KATEGORI USER · ${namaBulan(widget.tanggal).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('HP'), icon: Icon(Icons.smartphone)),
              ButtonSegment(value: true, label: Text('IoT'), icon: Icon(Icons.watch)),
            ],
            selected: {_iot},
            onSelectionChanged: (s) => setState(() => _iot = s.first),
          ),
          const SizedBox(height: 8),
          if (total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada penjualan ${_iot ? 'IoT' : 'HP'} bulan ini', style: TextStyle(color: Colors.grey.shade600)),
            )
          else ...[
            Text('Total ${angka(total)} unit', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  for (final k in kategori)
                    if (unit(k) > 0)
                      Expanded(flex: (unit(k) * 1000 ~/ total).clamp(1, 1000), child: Container(color: _warna[k])),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            for (final k in kategori)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _warna[k]!.withValues(alpha: 0.15),
                    child: Icon(_ikon[k], size: 16, color: _warna[k]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${rupiah(value(k))}${hari(k) > 0 ? ' · +${angka(hari(k))} hari ini' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ]),
                  ),
                  Text('${angka(unit(k))} unit', style: const TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${(unit(k) / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold, color: _warna[k]),
                    ),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
