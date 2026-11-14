import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Kartu "Insentif hari ini" di dashboard PC: insentif HP & IoT dari penjualan tanggal itu.
/// Ketuk untuk rincian per penjualan. HP dikali persen tier sementara (estimasi bulan berjalan).
class InsentifHariCard extends StatefulWidget {
  final int storeId;
  final DateTime tanggal;
  const InsentifHariCard({super.key, required this.storeId, required this.tanggal});

  @override
  State<InsentifHariCard> createState() => _InsentifHariCardState();
}

class _InsentifHariCardState extends State<InsentifHariCard> {
  Map<String, dynamic>? _r;
  bool _gagal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Session.db
          .rpc('insentif_harian', params: {'p_store': widget.storeId, 'p_tanggal': ymd(widget.tanggal)}));
      if (mounted) setState(() => _r = r);
    } catch (_) {
      if (mounted) setState(() => _gagal = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (_gagal || (r != null && r['ada_aturan'] != true)) return const SizedBox.shrink();
    if (r == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    final hp = toNum(r['total_hp_tier']);
    final iot = toNum(r['total_iot']);
    final c = Colors.teal.shade700;
    final hariIni = isSameDay(widget.tanggal, wibToday());
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _rincian(context, r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(backgroundColor: c.withValues(alpha: 0.12), child: Icon(Icons.savings, color: c)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hariIni ? 'Insentif hari ini' : 'Insentif ${tglPendek(widget.tanggal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(rupiah(hp + iot), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
                Text('HP ${rupiah(hp)} · IoT ${rupiah(iot)} · ketuk untuk rincian',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }

  void _rincian(BuildContext context, Map<String, dynamic> r) {
    final rows = asList(r['rows']);
    final persen = toNum(r['persen_hp']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('Insentif ${hariTgl(widget.tanggal)}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Insentif HP dikali ${persen.toStringAsFixed(0)}% (tier sementara ${r['tier'] ?? '-'}); '
            'IoT selalu 100%. Angka akhir mengikuti tier di akhir bulan.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty) const EmptyState(icon: Icons.receipt_long, text: 'Belum ada penjualan'),
          for (final x in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(x['tipe'] == 'HP' ? Icons.smartphone : Icons.watch, size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${x['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('x${x['qty']} · ${rupiah(toNum(x['per_unit']))}/unit',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ]),
                ),
                Text(rupiah(toNum(x['insentif'])), style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
          const Divider(height: 24),
          _baris('Insentif HP penuh', rupiah(toNum(r['total_hp']))),
          _baris('Insentif HP x ${persen.toStringAsFixed(0)}%', rupiah(toNum(r['total_hp_tier'])), tebal: true),
          _baris('Insentif IoT (100%)', rupiah(toNum(r['total_iot'])), tebal: true),
          const Divider(height: 16),
          _baris('TOTAL', rupiah(toNum(r['total_hp_tier']) + toNum(r['total_iot'])), tebal: true),
        ]),
      ),
    );
  }

  Widget _baris(String a, String b, {bool tebal = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: tebal ? FontWeight.bold : null))),
          Text(b, style: TextStyle(fontWeight: tebal ? FontWeight.bold : FontWeight.w600)),
        ]),
      );
}
