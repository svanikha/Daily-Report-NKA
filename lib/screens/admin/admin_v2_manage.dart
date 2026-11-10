import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

// ---------------------------------------------------------------------
// JADWAL OFFDAY & IZIN (mingguan, semua PC dalam satu layar)
// ---------------------------------------------------------------------
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
      final res = await Future.wait<dynamic>([
        db.from('profiles').select('id,nama,stores(nama)').eq('role', 'pc').eq('aktif', true).order('nama'),
        db.from('pc_day_status').select('pc_id,tanggal,status').gte('tanggal', ymd(_week)).lte('tanggal', ymd(addDays(_week, 6))),
      ]);
      _pcs = asList(res[0]);
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
      final rows = asList(await db
          .from('pc_day_status')
          .select('pc_id,tanggal,status')
          .gte('tanggal', ymd(prev))
          .lte('tanggal', ymd(addDays(prev, 6))));
      final data = [
        for (final r in rows)
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
                  const InfoBanner('Ketuk kotak untuk mengganti: kosong (kerja) → Offday → Izin → kosong. '
                      'Di hari offday/izin semua kewajiban PC di aplikasi nonaktif.'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Row(children: [
                          const SizedBox(width: 96),
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
                                width: 96,
                                child: Text('${p['nama']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
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

// ---------------------------------------------------------------------
// LOKASI TOKO (koordinat + radius)
// ---------------------------------------------------------------------
class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stores = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _stores = asList(await Session.db.from('stores').select().order('nama'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final lat = TextEditingController(text: s['latitude']?.toString() ?? '');
    final lng = TextEditingController(text: s['longitude']?.toString() ?? '');
    final rad = TextEditingController(text: '${s['radius_m'] ?? 100}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s['nama']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude')),
          TextField(controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude')),
          TextField(controller: rad, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radius (meter)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final la = double.tryParse(lat.text.trim().replaceAll(',', '.'));
    final lo = double.tryParse(lng.text.trim().replaceAll(',', '.'));
    final r = int.tryParse(rad.text.trim()) ?? 0;
    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180 || r < 10) {
      if (mounted) showMsg(context, 'Koordinat atau radius tidak valid');
      return;
    }
    try {
      await Session.db.from('stores').update({'latitude': la, 'longitude': lo, 'radius_m': r}).eq('id', s['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lokasi toko')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  const InfoBanner('Dipakai untuk tanda "Di luar toko" pada foto dan syarat tombol Kembali ke Toko. '
                      'PC perlu membuka ulang aplikasi agar perubahan terbaca.'),
                  for (final s in _stores)
                    Card(
                      child: ListTile(
                        title: Text('${s['nama']}'),
                        subtitle: Text(s['latitude'] == null
                            ? 'Koordinat belum diatur'
                            : '${s['latitude']}, ${s['longitude']} · radius ${s['radius_m']} m'),
                        trailing: const Icon(Icons.edit_location_alt),
                        onTap: () => _edit(s),
                      ),
                    ),
                ]),
    );
  }
}

// ---------------------------------------------------------------------
// ITEM CHECKLIST STANDAR TOKO
// ---------------------------------------------------------------------
class ChecklistItemsScreen extends StatefulWidget {
  const ChecklistItemsScreen({super.key});

  @override
  State<ChecklistItemsScreen> createState() => _ChecklistItemsScreenState();
}

class _ChecklistItemsScreenState extends State<ChecklistItemsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _items = asList(await Session.db.from('checklist_items').select().order('urutan').order('id'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(Map<String, dynamic>? it) async {
    final nama = TextEditingController(text: it?['nama'] ?? '');
    final ket = TextEditingController(text: it?['keterangan'] ?? '');
    final urut = TextEditingController(text: '${it?['urutan'] ?? (_items.length + 1)}');
    var aktif = it?['aktif'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(it == null ? 'Tambah item' : 'Ubah item'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nama, decoration: const InputDecoration(labelText: 'Nama item *')),
            TextField(controller: ket, decoration: const InputDecoration(labelText: 'Yang dicek')),
            TextField(controller: urut, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Urutan')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif'),
              value: aktif,
              onChanged: (v) => setD(() => aktif = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nama.text.trim().isEmpty) {
      if (mounted) showMsg(context, 'Nama item wajib diisi');
      return;
    }
    final data = {
      'nama': nama.text.trim(),
      'keterangan': ket.text.trim().isEmpty ? null : ket.text.trim(),
      'urutan': int.tryParse(urut.text.trim()) ?? 0,
      'aktif': aktif,
    };
    try {
      if (it == null) {
        await Session.db.from('checklist_items').insert(data);
      } else {
        await Session.db.from('checklist_items').update(data).eq('id', it['id'] as int);
      }
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item checklist toko')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Tambah item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                  const InfoBanner('Item nonaktif tidak tampil di aplikasi PC dan tidak dihitung di rekap.'),
                  for (final it in _items)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${it['urutan']}')),
                        title: Text('${it['nama']}'),
                        subtitle: Text('${it['keterangan'] ?? ''}'),
                        trailing: it['aktif'] == true
                            ? Pill('Aktif', color: Colors.green.shade700)
                            : Pill('Nonaktif', color: Colors.grey.shade700),
                        onTap: () => _edit(it),
                      ),
                    ),
                ]),
    );
  }
}
