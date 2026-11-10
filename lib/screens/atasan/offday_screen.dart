import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Jadwal offday & izin PC per minggu. Trainer: PC di areanya. PIC NKA: semua PC.
class OffdayScreen extends StatefulWidget {
  const OffdayScreen({super.key});

  @override
  State<OffdayScreen> createState() => _OffdayScreenState();
}

class _OffdayScreenState extends State<OffdayScreen> {
  late DateTime _week = _mondayOf(wibToday());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pcs = [];
  final Map<String, String> _status = {}; // "pcId|yyyy-MM-dd" -> offday | izin

  static DateTime _mondayOf(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));
  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(_week, i)];

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
      final me = Session.current!;
      final res = await Future.wait<dynamic>([
        db.from('profiles').select('id,nama,store_id,stores(nama,area_id)').eq('role', 'pc').eq('aktif', true).order('nama'),
        db.from('pc_day_status').select('pc_id,tanggal,status').gte('tanggal', ymd(_week)).lte('tanggal', ymd(addDays(_week, 6))),
      ]);
      _pcs = asList(res[0]).where((p) {
        if (me.isPic) return true;
        return toNum(asMap(p['stores'])['area_id']).toInt() == me.areaId;
      }).toList();
      _status.clear();
      for (final r in asList(res[1])) {
        _status['${r['pc_id']}|${r['tanggal']}'] = '${r['status']}';
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cycle(String pcId, DateTime d) async {
    final key = '$pcId|${ymd(d)}';
    final now = _status[key];
    final next = now == null ? 'offday' : (now == 'offday' ? 'izin' : null);
    setState(() {
      if (next == null) {
        _status.remove(key);
      } else {
        _status[key] = next;
      }
    });
    try {
      final db = Session.db;
      if (next == null) {
        await db.from('pc_day_status').delete().eq('pc_id', pcId).eq('tanggal', ymd(d));
      } else {
        await db.from('pc_day_status').upsert(
          {'pc_id': pcId, 'tanggal': ymd(d), 'status': next, 'dibuat_oleh': Session.current?.id},
          onConflict: 'pc_id,tanggal',
        );
      }
    } catch (e) {
      if (mounted) showErr(context, e);
      _load();
    }
  }

  Future<void> _copyPrevWeek() async {
    final ok = await confirmDialog(context, 'Salin dari minggu lalu?',
        'Jadwal offday/izin minggu lalu disalin ke minggu ini. Jadwal yang sudah ada di minggu ini tetap.');
    if (!ok) return;
    try {
      final db = Session.db;
      final prev = addDays(_week, -7);
      final ids = _pcs.map((p) => p['id'] as String).toSet();
      final rows = asList(await db
          .from('pc_day_status')
          .select('pc_id,tanggal,status')
          .gte('tanggal', ymd(prev))
          .lte('tanggal', ymd(addDays(prev, 6))));
      final data = [
        for (final r in rows)
          if (ids.contains(r['pc_id']))
            {
              'pc_id': r['pc_id'],
              'tanggal': ymd(addDays(parseDate('${r['tanggal']}'), 7)),
              'status': r['status'],
              'dibuat_oleh': Session.current?.id,
            }
      ].where((x) => !_status.containsKey('${x['pc_id']}|${x['tanggal']}')).toList();
      if (data.isNotEmpty) await db.from('pc_day_status').upsert(data, onConflict: 'pc_id,tanggal');
      if (mounted) showMsg(context, '${data.length} jadwal disalin');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal offday & izin'),
        actions: [IconButton(onPressed: _copyPrevWeek, icon: const Icon(Icons.copy_all), tooltip: 'Salin dari minggu lalu')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Row(children: [
                    IconButton(
                      onPressed: () {
                        _week = addDays(_week, -7);
                        _load();
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text('${tgl(_week)} - ${tgl(addDays(_week, 6))}',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () {
                        _week = addDays(_week, 7);
                        _load();
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ]),
                  const InfoBanner('Ketuk kotak: kosong (kerja) → Offday → Izin → kosong. '
                      'Di hari offday/izin PC full off: tidak wajib lapor dan tidak dihitung "tidak lapor".'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Row(children: [
                          const SizedBox(width: 104),
                          for (final d in _days)
                            Expanded(
                              child: Column(children: [
                                Text(const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d.weekday - 1],
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text('${d.day}', style: const TextStyle(fontSize: 11)),
                              ]),
                            ),
                        ]),
                        const Divider(),
                        for (final p in _pcs)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              SizedBox(
                                width: 104,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${p['nama']}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text('${asMap(p['stores'])['nama'] ?? ''}'.replaceFirst('Erafone ', ''),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                                ]),
                              ),
                              for (final d in _days) Expanded(child: _cell('${p['id']}', d)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ]),
    );
  }

  Widget _cell(String pcId, DateTime d) {
    final s = _status['$pcId|${ymd(d)}'];
    final color = s == 'offday' ? Colors.teal : (s == 'izin' ? Colors.orange.shade700 : Colors.grey.shade200);
    return InkWell(
      onTap: () => _cycle(pcId, d),
      child: Container(
        height: 34,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(s == 'offday' ? 'Off' : (s == 'izin' ? 'Izin' : ''),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
