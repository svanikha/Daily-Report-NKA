import 'package:flutter/material.dart';

import '../data/nka.dart';
import '../utils.dart';

/// Timegone: tanggal / jumlah hari di bulan itu (10/30 = 33%).
class TimegoneBar extends StatelessWidget {
  final HariKerja hk;

  /// Tampilkan sisa hari kerja (khusus toko/PC; TL/PIC cukup timegone).
  final bool tampilSisa;
  const TimegoneBar({super.key, required this.hk, this.tampilSisa = true});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.hourglass_bottom, color: c),
            const SizedBox(width: 8),
            const Expanded(child: Text('Timegone', style: TextStyle(fontWeight: FontWeight.bold))),
            Text(hk.timegoneText, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: hk.timegone / 100, minHeight: 6, color: c, backgroundColor: Colors.grey.shade200),
          ),
          if (tampilSisa) ...[
            const SizedBox(height: 6),
            Text(
              'Sisa hari kerja: ${hk.sisaHariKerja} hari'
              '${hk.offdaySisa > 0 ? ' (sisa ${hk.totalHari - hk.hariKe + 1} hari dikurangi ${hk.offdaySisa} offday)' : ' (termasuk hari ini)'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

/// Ringkasan sell-out toko/PC: capai unit & value, persentase, kekurangan per hari kerja,
/// tipe fokus, dan IoT. Persentase hijau jika sudah di atas timegone.
class SellOutCard extends StatelessWidget {
  final Map<String, dynamic> hari;
  final Map<String, dynamic> bulan;
  final Map<String, dynamic> target;
  final HariKerja hk;
  const SellOutCard({super.key, required this.hari, required this.bulan, required this.target, required this.hk});

  @override
  Widget build(BuildContext context) {
    final tUnit = toNum(target['unit']);
    final tValue = toNum(target['value']);
    final tIot = toNum(target['iot']);
    final unit = toNum(bulan['unit']);
    final value = toNum(bulan['value']);
    final iot = toNum(bulan['iot']);
    return Column(children: [
      _box(context, 'SELL OUT HP', Icons.smartphone, [
        _row('Sell out hari ini', '${angka(toNum(hari['unit']))} unit · ${rupiah(toNum(hari['value']))}'),
        _capai('Capai unit', unit, tUnit, (v) => '${angka(v)} unit'),
        _capai('Capai value', value, tValue, rupiah),
        _kurang('Kekurangan unit / hari kerja', tUnit, unit, (v) => '${angka(v.ceil())} unit'),
        _kurang('Kekurangan value / hari kerja', tValue, value, (v) => rupiah(v.round())),
        const Divider(height: 16),
        _capai('Tipe fokus A7 Pro', toNum(bulan['fokus_a7pro']), toNum(target['fokus_a7pro']), (v) => '${angka(v)} unit'),
        _kurang('Kekurangan A7 Pro / hari kerja', toNum(target['fokus_a7pro']), toNum(bulan['fokus_a7pro']),
            (v) => '${angka(v.ceil())} unit'),
        _capai('Tipe fokus Reno 16', toNum(bulan['fokus_reno16']), toNum(target['fokus_reno16']), (v) => '${angka(v)} unit'),
        _kurang('Kekurangan Reno 16 / hari kerja', toNum(target['fokus_reno16']), toNum(bulan['fokus_reno16']),
            (v) => '${angka(v.ceil())} unit'),
      ]),
      _box(context, 'SELL OUT IoT', Icons.watch, [
        _row('Sell out hari ini', '${angka(toNum(hari['iot']))} unit · ${rupiah(toNum(hari['iot_value']))}'),
        _capai('Capai unit', iot, tIot, (v) => '${angka(v)} unit'),
        _row('Capai value', rupiah(toNum(bulan['iot_value']))),
        _kurang('Kekurangan unit / hari kerja', tIot, iot, (v) => '${angka(v.ceil())} unit'),
      ]),
    ]);
  }

  Widget _box(BuildContext context, String title, IconData icon, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
      );

  /// Capai bulan ini vs target + persentase. Hijau jika >= timegone.
  Widget _capai(String label, num capai, num target, String Function(num) fmt) {
    if (target <= 0) return _row(label, '${fmt(capai)} (target belum diatur)');
    final p = capai / target * 100;
    final c = p >= hk.timegone ? Colors.green.shade700 : Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text('${fmt(capai)} / ${fmt(target)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('${p.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
          ),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (p / 100).clamp(0.0, 1.0).toDouble(),
            minHeight: 5,
            color: c,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ]),
    );
  }

  Widget _kurang(String label, num target, num capai, String Function(num) fmt) {
    if (target <= 0) return const SizedBox.shrink();
    if (capai >= target) return _row(label, 'Target tercapai', color: Colors.green.shade700);
    if (hk.sisaHariKerja <= 0) return _row(label, 'Kurang ${fmt(target - capai)} (tidak ada hari kerja)', color: Colors.red.shade700);
    return _row(label, '${fmt(hk.perHari(target, capai))} (${hk.sisaHariKerja} hari)', color: Colors.red.shade700);
  }
}
