import 'package:flutter/material.dart';

import '../data/nka.dart';
import '../services/session.dart';
import '../utils.dart';
import '../widgets/foto_thumb.dart';
import '../widgets/widgets.dart';

// =====================================================================
// Bagian bersama: pilih bulan + pilih toko (untuk atasan)
// =====================================================================

/// Toko yang bisa dilihat akun ini (PIC: semua, TL/Trainer: areanya, PC: tokonya).
Future<List<Map<String, dynamic>>> tokoCakupan() async {
  final me = Session.current!;
  final rows = asList(await Session.db.from('stores').select('id,nama,area_id').eq('aktif', true).order('area_id').order('id'));
  return rows
      .where((s) =>
          me.isPic ||
          (me.isPc ? toNum(s['id']).toInt() == me.storeId : toNum(s['area_id']).toInt() == me.areaId))
      .toList();
}

class _PilihBulanToko extends StatelessWidget {
  final DateTime bulan;
  final ValueChanged<DateTime> onBulan;
  final List<Map<String, dynamic>> toko;
  final int? storeId;
  final ValueChanged<int?>? onToko;
  const _PilihBulanToko({
    required this.bulan,
    required this.onBulan,
    required this.toko,
    required this.storeId,
    this.onToko,
  });

  @override
  Widget build(BuildContext context) {
    final maju = DateTime(bulan.year, bulan.month + 1, 1);
    return Column(children: [
      Row(children: [
        IconButton(onPressed: () => onBulan(DateTime(bulan.year, bulan.month - 1, 1)), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(namaBulan(bulan), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        IconButton(
          onPressed: maju.isAfter(wibToday()) ? null : () => onBulan(maju),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      if (onToko != null && toko.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: DropdownButtonFormField<int?>(
            initialValue: storeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Toko', prefixIcon: Icon(Icons.store), isDense: true),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Semua toko')),
              for (final t in toko) DropdownMenuItem<int?>(value: toNum(t['id']).toInt(), child: Text('${t['nama']}')),
            ],
            onChanged: onToko,
          ),
        ),
    ]);
  }
}

Map<String, List<Map<String, dynamic>>> _fotoPerRef(List<Map<String, dynamic>> fotos) {
  final m = <String, List<Map<String, dynamic>>>{};
  for (final f in fotos) {
    m.putIfAbsent('${f['ref_id']}', () => []).add(f);
  }
  return m;
}

Future<List<Map<String, dynamic>>> _fotoUntuk(String tabel, List<String> ids) async {
  if (ids.isEmpty) return [];
  return asList(await Session.db
      .from('photos')
      .select('ref_id,path,sumber,flags,created_at')
      .eq('ref_tabel', tabel)
      .inFilter('ref_id', ids)
      .order('created_at'));
}

// =====================================================================
// RIWAYAT CEK LIMIT
// =====================================================================

/// Semua pengajuan cek limit leasing per bulan: ringkasan per leasing + daftar lengkap dengan foto.
class RiwayatCekLimitScreen extends StatefulWidget {
  /// null = semua toko di cakupan (atasan)
  final int? storeId;
  final String? judul;
  const RiwayatCekLimitScreen({super.key, this.storeId, this.judul});

  @override
  State<RiwayatCekLimitScreen> createState() => _RiwayatCekLimitScreenState();
}

class _RiwayatCekLimitScreenState extends State<RiwayatCekLimitScreen> {
  DateTime _bulan = DateTime(wibToday().year, wibToday().month, 1);
  late int? _store = widget.storeId;
  List<Map<String, dynamic>> _toko = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _foto = {};
  bool _loading = true;
  String? _error;
  String _leasing = 'Semua';

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
      if (_toko.isEmpty && widget.storeId == null) _toko = await tokoCakupan();
      final akhir = DateTime(_bulan.year, _bulan.month + 1, 0);
      var q = Session.db
          .from('leasing_checks')
          .select('id,tanggal,leasing,hasil,limit_disetujui,created_at,store_id,stores(nama),profiles!leasing_checks_diinput_oleh_fkey(nama)')
          .gte('tanggal', ymd(_bulan))
          .lte('tanggal', ymd(akhir));
      if (_store != null) q = q.eq('store_id', _store!);
      _rows = asList(await q.order('tanggal', ascending: false).order('created_at', ascending: false));
      _foto = _fotoPerRef(await _fotoUntuk('leasing_checks', [for (final r in _rows) '${r['id']}']));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => _leasing == 'Semua' || r['leasing'] == _leasing).toList();
    final approve = list.where((r) => r['hasil'] == 'Approve').length;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Riwayat cek limit'),
          if (widget.judul != null) Text(widget.judul!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: Column(children: [
        _PilihBulanToko(
          bulan: _bulan,
          onBulan: (b) {
            _bulan = b;
            _load();
          },
          toko: _toko,
          storeId: _store,
          onToko: widget.storeId == null
              ? (v) {
                  _store = v;
                  _load();
                }
              : null,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final l in ['Semua', ...leasingList])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(l), selected: _leasing == l, onSelected: (_) => setState(() => _leasing = l)),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetry(error: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(children: [
                              Row(children: [
                                Expanded(child: _kpi('Pengajuan', '${list.length}')),
                                Expanded(child: _kpi('Approve', '$approve', c: Colors.green.shade700)),
                                Expanded(child: _kpi('Reject', '${list.length - approve}', c: Colors.red.shade700)),
                              ]),
                              if (_leasing == 'Semua' && _rows.isNotEmpty) ...[
                                const Divider(height: 18),
                                for (final l in leasingList)
                                  if (_rows.any((r) => r['leasing'] == l)) _ringkasLeasing(l),
                              ],
                            ]),
                          ),
                        ),
                        if (list.isEmpty) const EmptyState(icon: Icons.fact_check, text: 'Belum ada cek limit bulan ini'),
                        for (final r in list) _item(r),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _kpi(String label, String v, {Color? c}) => Column(children: [
        Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _ringkasLeasing(String l) {
    final rows = _rows.where((r) => r['leasing'] == l).toList();
    final ok = rows.where((r) => r['hasil'] == 'Approve').length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text('${rows.length}x · ', style: const TextStyle(fontSize: 12)),
        Text('$ok approve', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
        Text(' · ${rows.length - ok} reject', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
      ]),
    );
  }

  Widget _item(Map<String, dynamic> r) {
    final ok = r['hasil'] == 'Approve';
    final c = ok ? Colors.green.shade700 : Colors.red.shade700;
    final foto = _foto['${r['id']}'] ?? const <Map<String, dynamic>>[];
    final jam = r['created_at'] == null ? '' : jamMenit(parseWib('${r['created_at']}'));
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${r['leasing']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 8),
                Pill(ok ? 'Approve' : 'Reject', color: c),
              ]),
              if (ok) Text('Limit ${rupiah(toNum(r['limit_disetujui']))}', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              Text(
                [
                  '${tglPendek(parseDate('${r['tanggal']}'))} $jam',
                  if (_store == null) '${asMap(r['stores'])['nama'] ?? ''}',
                  '${asMap(r['profiles'])['nama'] ?? ''}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          if (foto.isNotEmpty)
            FotoThumb(path: '${foto.first['path']}', size: 56, onTap: () => bukaFoto(context, foto, 'Cek limit ${r['leasing']}')),
        ]),
      ),
    );
  }
}

// =====================================================================
// RIWAYAT ISTIRAHAT
// =====================================================================

/// Riwayat istirahat PC per bulan: jam mulai/kembali, durasi, keterlambatan, dan selfie.
class RiwayatIstirahatScreen extends StatefulWidget {
  final int? storeId;
  final String? judul;
  const RiwayatIstirahatScreen({super.key, this.storeId, this.judul});

  @override
  State<RiwayatIstirahatScreen> createState() => _RiwayatIstirahatScreenState();
}

class _RiwayatIstirahatScreenState extends State<RiwayatIstirahatScreen> {
  DateTime _bulan = DateTime(wibToday().year, wibToday().month, 1);
  late int? _store = widget.storeId;
  List<Map<String, dynamic>> _toko = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _foto = {};
  bool _loading = true;
  String? _error;
  bool _telatSaja = false;

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
      if (_toko.isEmpty && widget.storeId == null) _toko = await tokoCakupan();
      final akhir = DateTime(_bulan.year, _bulan.month + 1, 0);
      var q = Session.db
          .from('breaks')
          .select('id,tanggal,durasi_menit,mulai,selesai,terlambat_menit,jarak_mulai_m,jarak_kembali_m,store_id,'
              'stores(nama),profiles!breaks_pc_id_fkey(nama)')
          .gte('tanggal', ymd(_bulan))
          .lte('tanggal', ymd(akhir));
      if (_store != null) q = q.eq('store_id', _store!);
      _rows = asList(await q.order('tanggal', ascending: false).order('mulai', ascending: false));
      _foto = _fotoPerRef(await _fotoUntuk('breaks', [for (final r in _rows) '${r['id']}']));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _telat(Map<String, dynamic> r) => toNum(r['terlambat_menit']) > 0 || r['selesai'] == null;

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => !_telatSaja || _telat(r)).toList();
    final telat = _rows.where(_telat).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Riwayat istirahat'),
          if (widget.judul != null) Text(widget.judul!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: Column(children: [
        _PilihBulanToko(
          bulan: _bulan,
          onBulan: (b) {
            _bulan = b;
            _load();
          },
          toko: _toko,
          storeId: _store,
          onToko: widget.storeId == null
              ? (v) {
                  _store = v;
                  _load();
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            ChoiceChip(label: Text('Semua (${_rows.length})'), selected: !_telatSaja, onSelected: (_) => setState(() => _telatSaja = false)),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('Telat / tidak kembali ($telat)'),
              selected: _telatSaja,
              onSelected: (_) => setState(() => _telatSaja = true),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetry(error: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                        if (list.isEmpty) const EmptyState(icon: Icons.free_breakfast, text: 'Belum ada istirahat'),
                        for (final r in list) _item(r),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _item(Map<String, dynamic> r) {
    final mulai = parseWib('${r['mulai']}');
    final selesai = r['selesai'] == null ? null : parseWib('${r['selesai']}');
    final telat = toNum(r['terlambat_menit']).toInt();
    final durasi = toNum(r['durasi_menit']);
    final foto = _foto['${r['id']}'] ?? const <Map<String, dynamic>>[];
    final String status;
    final Color c;
    if (selesai == null) {
      status = 'Belum kembali';
      c = Colors.red.shade700;
    } else if (telat > 0) {
      status = 'Telat $telat mnt';
      c = Colors.red.shade700;
    } else {
      status = 'Tepat waktu';
      c = Colors.green.shade700;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${asMap(r['profiles'])['nama'] ?? 'PC'} · ${asMap(r['stores'])['nama'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Pill(status, color: c),
          ]),
          Text(
            '${hariTgl(parseDate('${r['tanggal']}'))} · ${labelDurasi(durasi)} · '
            '${jamMenit(mulai)} - ${selesai == null ? '…' : jamMenit(selesai)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (r['jarak_mulai_m'] != null || r['jarak_kembali_m'] != null)
            Text(
              'Jarak dari toko: keluar ${r['jarak_mulai_m'] ?? '-'} m · kembali ${r['jarak_kembali_m'] ?? '-'} m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (foto.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              for (var i = 0; i < foto.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    FotoThumb(path: '${foto[i]['path']}', size: 72, onTap: () => bukaFoto(context, foto, 'Selfie istirahat')),
                    Text(i == 0 ? 'Mulai' : 'Kembali', style: const TextStyle(fontSize: 11)),
                  ]),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// =====================================================================
// GALERI FOTO
// =====================================================================

const _jenisFoto = <String, String>{
  'Semua': '',
  'Display': 'display_checks',
  'Istirahat': 'breaks',
  'Sosmed': 'social_activities',
  'Cek limit': 'leasing_checks',
};

String _labelRef(String t) => switch (t) {
      'display_checks' || 'display_reports' => 'Display',
      'breaks' => 'Istirahat',
      'social_activities' => 'Sosmed',
      'leasing_checks' => 'Cek limit',
      _ => t,
    };

/// Galeri semua foto PC (display, selfie istirahat, sosmed, cek limit) per bulan dan per toko.
class GaleriFotoScreen extends StatefulWidget {
  final int? storeId;
  const GaleriFotoScreen({super.key, this.storeId});

  @override
  State<GaleriFotoScreen> createState() => _GaleriFotoScreenState();
}

class _GaleriFotoScreenState extends State<GaleriFotoScreen> {
  DateTime _bulan = DateTime(wibToday().year, wibToday().month, 1);
  late int? _store = widget.storeId;
  List<Map<String, dynamic>> _toko = [];
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _jenis = 'Semua';

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
      if (_toko.isEmpty && widget.storeId == null) _toko = await tokoCakupan();
      final akhir = DateTime(_bulan.year, _bulan.month + 1, 1);
      var q = Session.db
          .from('photos')
          .select('id,ref_tabel,path,sumber,flags,created_at,store_id,stores(nama)')
          .gte('created_at', wibToUtcIso(_bulan))
          .lt('created_at', wibToUtcIso(akhir));
      if (_store != null) q = q.eq('store_id', _store!);
      final ref = _jenisFoto[_jenis]!;
      if (ref == 'display_checks') {
        q = q.inFilter('ref_tabel', ['display_checks', 'display_reports']);
      } else if (ref.isNotEmpty) {
        q = q.eq('ref_tabel', ref);
      }
      _rows = asList(await q.order('created_at', ascending: false).limit(500));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Kelompok per tanggal (WIB)
    final perTgl = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      perTgl.putIfAbsent(ymd(parseWib('${r['created_at']}')), () => []).add(r);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Galeri foto PC')),
      body: Column(children: [
        _PilihBulanToko(
          bulan: _bulan,
          onBulan: (b) {
            _bulan = b;
            _load();
          },
          toko: _toko,
          storeId: _store,
          onToko: widget.storeId == null
              ? (v) {
                  _store = v;
                  _load();
                }
              : null,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final j in _jenisFoto.keys)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(j),
                  selected: _jenis == j,
                  onSelected: (_) {
                    _jenis = j;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorRetry(error: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                        Text('${_rows.length} foto${_rows.length >= 500 ? ' (500 terbaru)' : ''}',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (_rows.isEmpty) const EmptyState(icon: Icons.photo_library, text: 'Belum ada foto'),
                        for (final e in perTgl.entries) ..._hari(e.key, e.value),
                      ]),
                    ),
        ),
      ]),
    );
  }

  List<Widget> _hari(String tgl, List<Map<String, dynamic>> fotos) => [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text('${hariTgl(parseDate(tgl))} · ${fotos.length} foto', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        LayoutBuilder(builder: (ctx, c) {
          final n = (c.maxWidth / 110).floor().clamp(3, 8);
          final s = (c.maxWidth - (n - 1) * 6) / n;
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < fotos.length; i++)
              SizedBox(
                width: s,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FotoThumb(
                    path: '${fotos[i]['path']}',
                    size: s,
                    onTap: () => bukaFoto(context, fotos.sublist(i), '${asMap(fotos[i]['stores'])['nama'] ?? ''}'),
                  ),
                  Text(
                    '${_labelRef('${fotos[i]['ref_tabel']}')} · ${jamMenit(parseWib('${fotos[i]['created_at']}'))}',
                    style: const TextStyle(fontSize: 10.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_store == null)
                    Text('${asMap(fotos[i]['stores'])['nama'] ?? ''}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis),
                ]),
              ),
          ]);
        }),
      ];
}
