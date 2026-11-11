import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// MS Allbrand: penjualan HP semua brand lain di toko yang sama, per brand dan
/// per segmen harga (< 3 jt, 3-6 jt, 6 jt up). Cukup angka unit, tanpa tipe.
///
/// Yang diisi = penjualan HARI INI (besok mulai dari 0 lagi). Todate = jumlah dari
/// tanggal 1 sampai hari ini, dihitung otomatis. Setiap perubahan tersimpan otomatis;
/// notifikasi ke atasan dikirim sekali saat menekan Selesai / keluar dari halaman.
class MsAllbrandScreen extends StatefulWidget {
  final TokoHari toko;
  const MsAllbrandScreen({super.key, required this.toko});

  @override
  State<MsAllbrandScreen> createState() => _MsAllbrandScreenState();
}

class _MsAllbrandScreenState extends State<MsAllbrandScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saveError;
  bool _terisi = false;
  DateTime? _tersimpan;
  List<Map<String, dynamic>> _brands = [];

  /// Hari ini: brandId -> segmen -> unit (yang diisi)
  final Map<int, Map<String, int>> _unit = {};

  /// Sebelum hari ini (tgl 1 s.d. kemarin): brandId -> segmen -> unit
  final Map<int, Map<String, int>> _lalu = {};

  /// Unit HP OPPO per segmen (dari harga jual): hari ini dan sebelum hari ini.
  final Map<String, num> _oppo = {for (final s in segmenList) s: 0};
  final Map<String, num> _oppoLalu = {for (final s in segmenList) s: 0};

  Timer? _debounce;
  bool _dirty = false; // ada perubahan yang belum tersimpan
  bool _perluNotif = false; // ada perubahan yang belum dikabarkan ke atasan

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Keluar tanpa menekan Selesai: simpan sisa perubahan + kabari atasan sekali.
    if ((_dirty || _perluNotif) && t.bolehIsiHarian) {
      final params = {'p_store': t.storeId, 'p_tanggal': t.tgl, 'p_detail': _detail(), 'p_notif': true};
      () async {
        try {
          await Session.db.rpc('simpan_ms_allbrand', params: params);
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  static String _segmenDariHarga(num harga) => harga < 3000000 ? 'lt3' : (harga < 6000000 ? '3to6' : 'gt6');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final awal = ymd(DateTime(t.tanggal.year, t.tanggal.month, 1));
      final res = await Future.wait<dynamic>([
        db.from('competitor_brands').select('id,nama').eq('aktif', true).order('urutan'),
        db
            .from('competitor_sales_detail')
            .select('tanggal,brand_id,segmen,unit')
            .eq('store_id', t.storeId)
            .gte('tanggal', awal)
            .lte('tanggal', t.tgl),
        db.from('competitor_sales').select('updated_at').eq('store_id', t.storeId).eq('tanggal', t.tgl).limit(1),
        db
            .from('sales')
            .select('tanggal,qty,harga')
            .eq('store_id', t.storeId)
            .gte('tanggal', awal)
            .lte('tanggal', t.tgl)
            .eq('tipe', 'HP'),
      ]);
      _brands = asList(res[0]);
      _unit.clear();
      _lalu.clear();
      for (final b in _brands) {
        _unit[toNum(b['id']).toInt()] = {for (final s in segmenList) s: 0};
        _lalu[toNum(b['id']).toInt()] = {for (final s in segmenList) s: 0};
      }
      for (final d in asList(res[1])) {
        final hariIni = '${d['tanggal']}' == t.tgl;
        final m = (hariIni ? _unit : _lalu)[toNum(d['brand_id']).toInt()];
        final s = '${d['segmen']}';
        if (m != null && m.containsKey(s)) m[s] = m[s]! + toNum(d['unit']).toInt();
      }
      final c = asList(res[2]);
      _terisi = c.isNotEmpty;
      _tersimpan = c.isEmpty || c.first['updated_at'] == null ? null : parseWib('${c.first['updated_at']}');
      for (final s in segmenList) {
        _oppo[s] = 0;
        _oppoLalu[s] = 0;
      }
      for (final r in asList(res[3])) {
        final s = _segmenDariHarga(toNum(r['harga']));
        final m = '${r['tanggal']}' == t.tgl ? _oppo : _oppoLalu;
        m[s] = (m[s] ?? 0) + toNum(r['qty']);
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _sumBrand(Map<int, Map<String, int>> m, int brand) =>
      (m[brand]?.values ?? const <int>[]).fold(0, (a, b) => a + b);
  int _sumSeg(Map<int, Map<String, int>> m, String seg) => m.values.fold(0, (a, x) => a + (x[seg] ?? 0));
  int _total(Map<int, Map<String, int>> m) => m.keys.fold(0, (a, b) => a + _sumBrand(m, b));

  int _todateBrandSeg(int brand, String seg) => (_unit[brand]?[seg] ?? 0) + (_lalu[brand]?[seg] ?? 0);

  List<Map<String, dynamic>> _detail() => [
        for (final e in _unit.entries)
          for (final s in segmenList)
            if ((e.value[s] ?? 0) > 0) {'brand_id': e.key, 'segmen': s, 'unit': e.value[s]},
      ];

  void _set(int brand, String seg, int v) {
    setState(() {
      _unit[brand]![seg] = v < 0 ? 0 : v;
      _dirty = true;
      _perluNotif = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () => _simpan(notif: false));
  }

  /// Simpan ke server. notif=false: autosave diam-diam; notif=true: kabari atasan.
  Future<bool> _simpan({required bool notif}) async {
    _debounce?.cancel();
    if (!t.bolehIsiHarian) return false;
    if (mounted) setState(() => _saving = true);
    final kirimDirty = _dirty;
    _dirty = false;
    try {
      await Session.db.rpc('simpan_ms_allbrand',
          params: {'p_store': t.storeId, 'p_tanggal': t.tgl, 'p_detail': _detail(), 'p_notif': notif});
      if (notif) _perluNotif = false;
      if (mounted) {
        setState(() {
          _terisi = true;
          _tersimpan = wibNow();
          _saveError = null;
        });
      }
      return true;
    } catch (e) {
      _dirty = _dirty || kirimDirty;
      if (mounted) setState(() => _saveError = errMsg(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selesai() async {
    if (_detail().isEmpty) {
      final ok = await confirmDialog(context, 'Semua brand 0?',
          'Simpan bahwa hari ini tidak ada penjualan brand lain di toko ini?', yes: 'Simpan');
      if (!ok) return;
    }
    final ok = await _simpan(notif: true);
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'MS Allbrand hari ini tersimpan');
      Navigator.pop(context, true);
    } else if (_saveError != null) {
      showMsg(context, _saveError!);
    }
  }

  Future<void> _ketik(int brand, String seg, String namaBrand) async {
    final c = TextEditingController(text: '${_unit[brand]![seg]}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$namaBrand · ${segmenLabel[seg]}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Terjual hari ini', suffixText: 'unit'),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    if (v != null) _set(brand, seg, v);
  }

  String _ms(num oppo, num lain) => oppo + lain > 0 ? '${(oppo / (oppo + lain) * 100).toStringAsFixed(0)}%' : '-';

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final oppoToday = _oppo.values.fold<num>(0, (a, b) => a + b);
    final oppoTodate = oppoToday + _oppoLalu.values.fold<num>(0, (a, b) => a + b);
    final lainToday = _total(_unit);
    final lainTodate = lainToday + _total(_lalu);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MS Allbrand'),
          Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      bottomNavigationBar: _loading || _error != null || !boleh
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _statusSimpan(),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: _saving ? null : _selesai,
                    icon: busyIcon(_saving, Icons.check),
                    label: const Text('Selesai'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Table(
                        columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          _row('', 'Today', 'Todate', header: true),
                          _row('OPPO', angka(oppoToday), angka(oppoTodate)),
                          _row('Brand lain', angka(lainToday), angka(lainTodate)),
                          _row('MS OPPO', _ms(oppoToday, lainToday), _ms(oppoTodate, lainTodate), tebal: true),
                          for (final s in segmenList)
                            _row(
                              'MS ${segmenLabel[s]}',
                              _ms(_oppo[s] ?? 0, _sumSeg(_unit, s)),
                              _ms((_oppo[s] ?? 0) + (_oppoLalu[s] ?? 0), _sumSeg(_unit, s) + _sumSeg(_lalu, s)),
                              kecil: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Isi unit HP brand lain yang terjual HARI INI per segmen harga. Todate (tgl 1 s.d. hari ini) '
                      'dijumlah otomatis. Besok isian mulai dari 0 lagi. Perubahan tersimpan otomatis.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final b in _brands) _brandCard(b, boleh),
                ]),
    );
  }

  Widget _statusSimpan() {
    final s = Theme.of(context).textTheme.bodySmall;
    if (_saving) return Text('Menyimpan…', style: s);
    if (_saveError != null) {
      return Text('Gagal menyimpan: $_saveError', style: s?.copyWith(color: Colors.red.shade700));
    }
    if (_dirty) return Text('Perubahan belum tersimpan…', style: s);
    if (_tersimpan != null) {
      return Text('Tersimpan otomatis ${jamMenit(_tersimpan!)} WIB', style: s?.copyWith(color: Colors.green.shade700));
    }
    return Text(_terisi ? 'Sudah diisi' : 'Belum diisi hari ini', style: s);
  }

  TableRow _row(String a, String b, String c, {bool header = false, bool tebal = false, bool kecil = false}) {
    final st = TextStyle(
      fontWeight: header || tebal ? FontWeight.bold : FontWeight.w600,
      fontSize: header ? 13 : (kecil ? 13 : 16),
      color: header ? Colors.grey.shade700 : null,
    );
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(a, style: TextStyle(fontWeight: tebal ? FontWeight.bold : null, fontSize: kecil ? 13 : 14)),
      ),
      Text(b, textAlign: TextAlign.center, style: st),
      Text(c, textAlign: TextAlign.center, style: st),
    ]);
  }

  Widget _brandCard(Map<String, dynamic> b, bool boleh) {
    final id = toNum(b['id']).toInt();
    final nama = '${b['nama']}';
    final today = _sumBrand(_unit, id);
    final todate = today + _sumBrand(_lalu, id);
    final c = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Text('Today $today', style: TextStyle(fontWeight: FontWeight.bold, color: today > 0 ? c : Colors.grey)),
            const SizedBox(width: 10),
            Text('Todate $todate', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ]),
          for (final s in segmenList)
            Row(children: [
              Expanded(child: Text(segmenLabel[s]!)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh && (_unit[id]![s] ?? 0) > 0 ? () => _set(id, s, _unit[id]![s]! - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              InkWell(
                onTap: boleh ? () => _ketik(id, s, nama) : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text('${_unit[id]![s]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh ? () => _set(id, s, (_unit[id]![s] ?? 0) + 1) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              SizedBox(
                width: 44,
                child: Text('${_todateBrandSeg(id, s)}',
                    textAlign: TextAlign.right, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              ),
            ]),
        ]),
      ),
    );
  }
}
