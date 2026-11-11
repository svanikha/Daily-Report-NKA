import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Kartu ringkas estimasi gaji bulan berjalan (dashboard PC & detail toko atasan).
/// Ketuk untuk rincian lengkap. Angka dihitung server dari pencapaian toko + aturan KPI area.
class EstimasiGajiCard extends StatefulWidget {
  final int storeId;
  final DateTime tanggal;
  final String? pcNama;
  const EstimasiGajiCard({super.key, required this.storeId, required this.tanggal, this.pcNama});

  @override
  State<EstimasiGajiCard> createState() => _EstimasiGajiCardState();
}

class _EstimasiGajiCardState extends State<EstimasiGajiCard> {
  Map<String, dynamic>? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EstimasiGajiCard old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId || old.tanggal != widget.tanggal) _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Session.db.rpc('estimasi_gaji', params: {'p_store': widget.storeId, 'p_tanggal': ymd(widget.tanggal)}));
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (_error != null) {
      // Belum ada aturan KPI di server (tahap2a.sql belum dijalankan): sembunyikan kartu.
      return const SizedBox.shrink();
    }
    if (r == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    if (r['ada_aturan'] != true) {
      return const Card(child: ListTile(leading: Icon(Icons.payments), title: Text('Estimasi gaji'),
          subtitle: Text('Aturan KPI & insentif area ini belum diatur')));
    }
    final c = Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EstimasiGajiScreen(data: r, tanggal: widget.tanggal, pcNama: widget.pcNama),
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.payments, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Estimasi gaji ${namaBulan(widget.tanggal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Pill('${r['tier'] ?? '-'}', color: c),
            ]),
            const SizedBox(height: 6),
            Text(rupiah(toNum(r['total'])), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)),
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 2, children: [
              _mini('Gaji pokok', toNum(r['gaji_pokok'])),
              _mini('Insentif', toNum(r['insentif_hp']) + toNum(r['insentif_iot'])),
              _mini('Bonus', toNum(r['total_bonus'])),
              _mini('Denda', -toNum(r['total_denda'])),
            ]),
            const SizedBox(height: 4),
            Text('Estimasi dari pencapaian s.d. ${tglPendek(widget.tanggal)} · ketuk untuk rincian',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _mini(String label, num v) => Text('$label ${v < 0 ? '-${rupiah(-v)}' : rupiah(v)}',
      style: TextStyle(fontSize: 12, color: v < 0 ? Colors.red.shade700 : null));
}

/// Rincian estimasi gaji: tier, gaji pokok, insentif HP & IoT, bonus, denda, dan target tier berikutnya.
class EstimasiGajiScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime tanggal;
  final String? pcNama;
  const EstimasiGajiScreen({super.key, required this.data, required this.tanggal, this.pcNama});

  @override
  Widget build(BuildContext context) {
    final r = data;
    final bonus = asList(r['bonus']);
    final denda = asList(r['denda']);
    final tiers = asList(r['tiers']);
    final value = toNum(r['value_hp']);
    final unit = toNum(r['unit_hp']);
    final persen = toNum(r['persen_insentif']);
    final gpu = r['gaji_persen_umr'];
    final c = Theme.of(context).colorScheme.primary;

    // Tier dengan syarat value lebih tinggi yang belum tercapai: tampilkan kekurangannya
    final naik = <Widget>[];
    for (final t in tiers) {
      final vmin = t['value_min'];
      if (vmin != null && toNum(vmin) > value) {
        naik.add(_baris('${t['nama']} (insentif ${toNum(t['persen'])}%)', 'kurang ${rupiah(toNum(vmin) - value)} value HP'));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Estimasi gaji ${namaBulan(tanggal)}'),
          Text('${pcNama ?? ''}${pcNama == null ? '' : ' · '}Area ${r['area'] ?? '-'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: c.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text('Estimasi diterima'),
              Text(rupiah(toNum(r['total'])), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)),
              const SizedBox(height: 4),
              Pill('${r['tier'] ?? '-'} · insentif HP ${persen.toStringAsFixed(0)}%', color: c),
              const SizedBox(height: 6),
              Text('Dihitung dari pencapaian s.d. ${hariTgl(tanggal)}. Angka akhir mengikuti perhitungan resmi.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        const SectionHeader('Pencapaian bulan ini'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _baris('Unit HP', '${angka(unit)} unit'),
              _baris('Value HP', rupiah(value)),
              _baris('A7 Pro + Reno 16', '${angka(toNum(r['unit_fokus']))} unit'),
              _baris('A7 Pro + Reno Series', '${angka(toNum(r['unit_a7_reno']))} unit'),
              _baris('IoT', '${angka(toNum(r['unit_iot']))} unit'),
            ]),
          ),
        ),
        const SectionHeader('Rincian gaji'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _baris('UMR area ${r['area'] ?? ''}', rupiah(toNum(r['umr']))),
              if (gpu != null)
                _baris('Gaji pokok (UMR x ${toNum(gpu).toStringAsFixed(0)}%)', rupiah(toNum(r['gaji_pokok'])), tebal: true)
              else ...[
                _baris('Potongan (${angka(unit)} unit HP)', '-${rupiah(toNum(r['potongan']))}', merah: toNum(r['potongan']) > 0),
                _baris('Gaji pokok', rupiah(toNum(r['gaji_pokok'])), tebal: true),
              ],
              const Divider(),
              _baris('Insentif HP penuh', rupiah(toNum(r['insentif_hp_penuh']))),
              _baris('Insentif HP x ${persen.toStringAsFixed(0)}% (${r['tier'] ?? '-'})', rupiah(toNum(r['insentif_hp'])), tebal: true),
              _baris('Insentif IoT (100%)', rupiah(toNum(r['insentif_iot'])), tebal: true),
              const Divider(),
              if (bonus.isEmpty) _baris('Bonus', 'Belum ada yang tercapai'),
              for (final b in bonus) _baris('Bonus: ${b['nama']}', '+${rupiah(toNum(b['jumlah']))}', hijau: true),
              if (denda.isEmpty) _baris('Denda', 'Tidak ada'),
              for (final d in denda)
                _baris('Denda: ${d['nama']} (capai ${angka(toNum(d['capai']))})', '-${rupiah(toNum(d['jumlah']))}', merah: true),
              const Divider(),
              _baris('ESTIMASI DITERIMA', rupiah(toNum(r['total'])), tebal: true),
            ]),
          ),
        ),
        if (naik.isNotEmpty) ...[
          const SectionHeader('Target naik tier'),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: naik))),
        ],
        const SectionHeader('Tabel tier'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final t in tiers)
                _baris(
                  '${t['nama']}${t['nama'] == r['tier'] ? '  ◀ sekarang' : ''}',
                  _syaratTier(t),
                  tebal: t['nama'] == r['tier'],
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _syaratTier(Map<String, dynamic> t) {
    String jt(num v) => '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)} jt';
    final parts = <String>[];
    final vmin = t['value_min'];
    final vmax = t['value_max'];
    if (vmin != null && vmax != null) {
      parts.add('${jt(toNum(vmin))} - <${jt(toNum(vmax))}');
    } else if (vmin != null) {
      parts.add('≥ ${jt(toNum(vmin))}');
    } else if (vmax != null) {
      parts.add('< ${jt(toNum(vmax))}');
    }
    if (t['unit_min'] != null) parts.add('unit ≥ ${t['unit_min']}');
    parts.add('insentif ${toNum(t['persen']).toStringAsFixed(0)}%');
    if (t['gaji_persen_umr'] != null) parts.add('gaji UMR x ${toNum(t['gaji_persen_umr']).toStringAsFixed(0)}%');
    return parts.join(' · ');
  }

  Widget _baris(String a, String b, {bool tebal = false, bool merah = false, bool hijau = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: tebal ? FontWeight.bold : null))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              b,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: tebal ? FontWeight.bold : FontWeight.w600,
                color: merah ? Colors.red.shade700 : (hijau ? Colors.green.shade700 : null),
              ),
            ),
          ),
        ]),
      );
}
