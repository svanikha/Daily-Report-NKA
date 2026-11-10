import 'package:flutter/material.dart';

import '../screens/pc/sale_form.dart';
import '../services/pc_sync.dart';
import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Status satu tanggal di kalender penjualan.
enum DayKind { future, berjalan, libur, hp, iotOnly, nosell }

class DayInfo {
  final DayKind kind;
  final bool tidakLapor; // NOSELL tanpa transaksi dan tanpa laporan nihil
  final String? libur; // offday | izin
  const DayInfo(this.kind, {this.tidakLapor = false, this.libur});
}

const dayColors = {
  DayKind.hp: Color(0xFF2E7D32),
  DayKind.iotOnly: Color(0xFFF9A825),
  DayKind.nosell: Color(0xFFC62828),
  DayKind.libur: Color(0xFFB0BEC5),
  DayKind.future: Color(0xFFECEFF1),
  DayKind.berjalan: Color(0xFFECEFF1),
};

/// Menentukan status setiap tanggal dalam bulan [bulan].
/// [sales] berisi tanggal, tipe, qty. [nihil] dan [libur] dikunci per tanggal (yyyy-MM-dd).
Map<String, DayInfo> computeDays(
  DateTime bulan,
  List<Map<String, dynamic>> sales,
  Set<String> nihil,
  Map<String, String> libur,
) {
  final today = wibToday();
  final hp = <String, num>{};
  final iot = <String, num>{};
  for (final s in sales) {
    final k = '${s['tanggal']}';
    if (s['tipe'] == 'HP') {
      hp[k] = (hp[k] ?? 0) + toNum(s['qty']);
    } else {
      iot[k] = (iot[k] ?? 0) + toNum(s['qty']);
    }
  }
  final out = <String, DayInfo>{};
  for (var d = monthStart(bulan); !d.isAfter(monthEnd(bulan)); d = addDays(d, 1)) {
    final k = ymd(d);
    if (libur.containsKey(k)) {
      out[k] = DayInfo(DayKind.libur, libur: libur[k]);
    } else if (d.isAfter(today)) {
      out[k] = const DayInfo(DayKind.future);
    } else if ((hp[k] ?? 0) > 0) {
      out[k] = const DayInfo(DayKind.hp);
    } else if ((iot[k] ?? 0) > 0) {
      out[k] = const DayInfo(DayKind.iotOnly);
    } else if (isSameDay(d, today) && pcInputOpen()) {
      out[k] = const DayInfo(DayKind.berjalan);
    } else {
      out[k] = DayInfo(DayKind.nosell, tidakLapor: !nihil.contains(k));
    }
  }
  return out;
}

/// Jumlah hari NOSELL, rekor beruntun, dan tidak lapor. Hari libur tidak memutus rekor.
({int nosell, int streak, int tidakLapor}) daySummary(Map<String, DayInfo> days) {
  var nosell = 0, streak = 0, best = 0, tidak = 0;
  final keys = days.keys.toList()..sort();
  for (final k in keys) {
    final d = days[k]!;
    if (d.kind == DayKind.nosell) {
      nosell++;
      streak++;
      if (d.tidakLapor) tidak++;
      if (streak > best) best = streak;
    } else if (d.kind != DayKind.libur) {
      streak = 0;
    }
  }
  return (nosell: nosell, streak: best, tidakLapor: tidak);
}

/// Kalender penjualan bulan berjalan untuk satu PC (tab Kalender di Report).
class NosellCalendar extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  const NosellCalendar({super.key, required this.pc, this.adminView = false});

  @override
  State<NosellCalendar> createState() => _NosellCalendarState();
}

class _NosellCalendarState extends State<NosellCalendar> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sales = [];
  Map<String, DayInfo> _days = {};

  @override
  bool get wantKeepAlive => true;

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
      final db = Session.db;
      final dari = ymd(monthStart());
      final sampai = ymd(monthEnd());
      final res = await Future.wait<dynamic>([
        db
            .from('sales')
            .select('id,tanggal,tipe,qty,nama_produk,subtotal')
            .eq('pc_id', widget.pc.id)
            .gte('tanggal', dari)
            .lte('tanggal', sampai),
        db.from('checkins').select('tanggal').eq('pc_id', widget.pc.id).eq('modul', 'report').gte('tanggal', dari).lte('tanggal', sampai),
        db.from('pc_day_status').select('tanggal,status').eq('pc_id', widget.pc.id).gte('tanggal', dari).lte('tanggal', sampai),
      ]);
      _sales = asList(res[0]);
      final nihil = asList(res[1]).map((r) => '${r['tanggal']}').toSet();
      final libur = {for (final r in asList(res[2])) '${r['tanggal']}': '${r['status']}'};
      _days = computeDays(wibToday(), _sales, nihil, libur);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openDay(String k) async {
    final rows = _sales.where((s) => s['tanggal'] == k).toList();
    // Penjualan bisa ditambah untuk tanggal berapa pun sampai hari ini.
    final canAdd = !widget.adminView && canPcEditSale(k);
    final tipe = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hariTgl(parseDate(k)), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Text('Tidak ada transaksi.'),
            for (final s in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${s['nama_produk']}'),
                subtitle: Text(s['tipe'] == 'HP' ? 'HP' : 'IoT'),
                trailing: Text('${s['qty']} unit · ${rupiah(toNum(s['subtotal']))}'),
              ),
            if (canAdd) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'HP'),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Tambah HP'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.pop(ctx, 'IOT'),
                    icon: const Icon(Icons.watch),
                    label: const Text('Tambah IoT'),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (tipe != null && mounted) await _add(tipe, parseDate(k));
  }

  Future<void> _add(String tipe, DateTime tanggal) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SaleForm(pc: widget.pc, tipe: tipe, tanggal: tanggal),
    ));
    if (ok == true) {
      _load();
      PcSync.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final sum = daySummary(_days);
    final first = monthStart();
    final lead = first.weekday - 1; // Senin = 0
    final keys = _days.keys.toList()..sort();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Text(namaBulan(first), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StatGrid(children: [
          StatCard(
            icon: Icons.block,
            label: 'Hari NOSELL bulan ini',
            value: '${sum.nosell} hari',
            sub: 'Tidak lapor ${sum.tidakLapor} hari',
            color: Colors.red.shade700,
          ),
          StatCard(icon: Icons.trending_down, label: 'Rekor NOSELL beruntun', value: '${sum.streak} hari', color: Colors.red.shade700),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [
                for (final h in const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'])
                  Expanded(child: Center(child: Text(h, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
              ]),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (var i = 0; i < lead; i++) const SizedBox(),
                  for (final k in keys) _cell(k, _days[k]!),
                ],
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 6, children: [
          _legend(dayColors[DayKind.hp]!, 'Ada penjualan HP'),
          _legend(dayColors[DayKind.iotOnly]!, 'Hanya IoT'),
          _legend(dayColors[DayKind.nosell]!, 'NOSELL'),
          _legend(dayColors[DayKind.libur]!, 'Offday / izin'),
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, backgroundColor: Color(0xFFC62828))),
            SizedBox(width: 4),
            Text('Tidak lapor', style: TextStyle(fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text('Hari ini berstatus "berjalan" sampai batas input 23.00 WIB. Ketuk tanggal untuk melihat atau menambah penjualan, termasuk tanggal yang sudah lewat.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _cell(String k, DayInfo d) {
    final date = parseDate(k);
    final dark = d.kind == DayKind.hp || d.kind == DayKind.nosell;
    final isToday = k == todayStr();
    return InkWell(
      onTap: d.kind == DayKind.future ? null : () => _openDay(k),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: dayColors[d.kind],
          borderRadius: BorderRadius.circular(6),
          border: isToday ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${date.day}', style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87)),
              if (d.kind == DayKind.libur)
                Text(d.libur == 'izin' ? 'Izin' : 'Off', style: const TextStyle(fontSize: 9)),
              if (d.kind == DayKind.berjalan) const Text('jalan', style: TextStyle(fontSize: 9)),
            ]),
          ),
          if (d.tidakLapor)
            const Positioned(
              right: 3,
              top: 1,
              child: Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}
