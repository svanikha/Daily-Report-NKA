import 'package:flutter/material.dart';

import '../utils.dart';

/// Ringkasan kewajiban activity: berapa target yang sudah terpenuhi.
({int penuh, int total}) hitungKewajiban(List<Map<String, dynamic>> rows) => (
      penuh: rows.where((r) => toNum(r['capai']) >= toNum(r['target'])).length,
      total: rows.length,
    );

/// Kartu kewajiban activity harian (target dari TL / Trainer / PIC area) dengan progres tiap item.
class KewajibanCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const KewajibanCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final h = hitungKewajiban(rows);
    final lengkap = h.penuh == h.total;
    final c = lengkap ? Colors.green.shade700 : Colors.orange.shade800;
    return Card(
      color: c.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(lengkap ? Icons.task_alt : Icons.flag, color: c),
            const SizedBox(width: 8),
            const Expanded(child: Text('Kewajiban activity hari ini', style: TextStyle(fontWeight: FontWeight.bold))),
            Text('${h.penuh}/${h.total}', style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          for (final r in rows) _item(r),
        ]),
      ),
    );
  }

  Widget _item(Map<String, dynamic> r) {
    final capai = toNum(r['capai']);
    final target = toNum(r['target']);
    final ok = capai >= target;
    final c = ok ? Colors.green.shade700 : Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text('${r['nama']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${angka(capai)} / ${angka(target)} ${r['satuan'] ?? ''}',
              style: TextStyle(fontWeight: FontWeight.bold, color: c)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: target > 0 ? (capai / target).clamp(0.0, 1.0).toDouble() : 0,
            minHeight: 5,
            color: c,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ]),
    );
  }
}
