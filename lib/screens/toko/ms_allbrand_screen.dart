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
/// Diisi PER TANGGAL. Tanggal bisa dipilih (tgl 1 s.d. hari ini di bulan berjalan), termasuk
/// tanggal yang sudah lewat. Isian tiap tanggal tetap tersimpan sampai dihapus.
/// Todate = jumlah semua tanggal dari tgl 1 s.d. hari ini. Setiap perubahan tersimpan otomatis;
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
  List<Map<String, dynamic>> _brands = [];

  /// brandId -> segmen yang berlaku (Apple hanya 6 jt up)
  final Map<int, List<String>> _segBrand = {};
  List<String> _seg(int brand) => _segBrand[brand] ?? segmenList;

  late DateTime _tgl = widget.toko.tanggal;
  late final DateTime _awal = DateTime(widget.toko.tanggal.year, widget.toko.tanggal.month, 1);

  /// tanggal (yyyy-mm-dd) -> brandId -> segmen -> unit
  final Map<String, Map<int, Map<String, int>>> _data = {};

  /// Tanggal yang sudah diisi (ada baris competitor_sales), dengan jam simpan terakhir.
  final Map<String, DateTime?> _terisi = {};

  /// tanggal -> segmen -> unit HP OPPO (dari harga jual)
  final Map<String, Map<String, num>> _oppo = {};

  Timer? _debounce;
  bool _dirty = false; // isian tanggal terpilih belum tersimpan
  final Set<String> _perluNotif = {}; // tanggal yang berubah tetapi belum dikabarkan ke atasan

  TokoHari get t => widget.toko;
  String get _key => ymd(_tgl);

  DateTime get _akhir {
    final today = wibToday();
    final akhirBulan = DateTime(_awal.year, _awal.month + 1, 0);
    return akhirBulan.isAfter(today) ? today : akhirBulan;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Keluar tanpa menekan Selesai: simpan sisa perubahan + kabari atasan sekali per tanggal.
    final tanggal = {..._perluNotif, if (_dirty) _key};
    for (final k in tanggal) {
      final params = {'p_store': t.storeId, 'p_tanggal': k, 'p_detail': _detail(k), 'p_notif': true};
      () async {
        try {
          await Session.db.rpc('simpan_ms_allbrand', params: params);
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  /// Boleh mengisi tanggal ini? (dijaga juga di server: can_write_ms)
  bool _boleh(DateTime d) {
    final me = Session.current;
    final today = wibToday();
    if (me == null || d.isAfter(today)) return false;
    if (me.isPic) return true;
    final bulanIni = d.year == today.year && d.month == today.month;
    return bulanIni && (me.isPc || me.isTl || me.isTrainer);
  }

  static String _segmenDariHarga(num harga) => harga < 3000000 ? 'lt3' : (harga < 6000000 ? '3to6' : 'gt6');

  Map<int, Map<String, int>> _kosong() => {
        for (final b in _brands) toNum(b['id']).toInt(): {for (final s in segmenList) s: 0},
      };

  Map<int, Map<String, int>> _hari(String k) => _data.putIfAbsent(k, _kosong);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final awal = ymd(_awal);
      final akhir = ymd(_akhir);
      final res = await Future.wait<dynamic>([
        db.from('competitor_brands').select('id,nama').eq('aktif', true).order('urutan'),
        db
            .from('competitor_sales_detail')
            .select('tanggal,brand_id,segmen,unit')
            .eq('store_id', t.storeId)
            .gte('tanggal', awal)
            .lte('tanggal', akhir),
        db
            .from('competitor_sales')
            .select('tanggal,updated_at')
            .eq('store_id', t.storeId)
            .gte('tanggal', awal)
            .lte('tanggal', akhir),
        db
            .from('sales')
            .select('tanggal,qty,harga')
            .eq('store_id', t.storeId)
            .gte('tanggal', awal)
            .lte('tanggal', akhir)
            .eq('tipe', 'HP'),
      ]);
      _brands = asList(res[0]);
      _segBrand
        ..clear()
        ..addAll({for (final b in _brands) toNum(b['id']).toInt(): segmenBrand('${b['nama']}')});
      _data.clear();
      _terisi.clear();
      _oppo.clear();
      for (final d in asList(res[1])) {
        final m = _hari('${d['tanggal']}')[toNum(d['brand_id']).toInt()];
        final s = '${d['segmen']}';
        final bid = toNum(d['brand_id']).toInt();
        if (m != null && m.containsKey(s) && _seg(bid).contains(s)) m[s] = m[s]! + toNum(d['unit']).toInt();
      }
      for (final c in asList(res[2])) {
        final k = '${c['tanggal']}';
        final w = c['updated_at'] == null ? null : parseWib('${c['updated_at']}');
        final lama = _terisi[k];
        _terisi[k] = lama == null || (w != null && w.isAfter(lama)) ? w : lama;
      }
      for (final r in asList(res[3])) {
        final m = _oppo.putIfAbsent('${r['tanggal']}', () => {for (final s in segmenList) s: 0});
        final s = _segmenDariHarga(toNum(r['harga']));
        m[s] = (m[s] ?? 0) + toNum(r['qty']);
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ---- hitungan -------------------------------------------------------
  int _sumBrand(Map<int, Map<String, int>> m, int brand) =>
      (m[brand]?.values ?? const <int>[]).fold(0, (a, b) => a + b);
  int _sumSeg(Map<int, Map<String, int>> m, String seg) => m.values.fold(0, (a, x) => a + (x[seg] ?? 0));
  int _total(Map<int, Map<String, int>> m) => m.keys.fold(0, (a, b) => a + _sumBrand(m, b));

  int _todateTotal() => _data.values.fold(0, (a, m) => a + _total(m));
  int _todateSeg(String s) => _data.values.fold(0, (a, m) => a + _sumSeg(m, s));
  int _todateBrand(int b) => _data.values.fold(0, (a, m) => a + _sumBrand(m, b));
  int _todateBrandSeg(int b, String s) => _data.values.fold(0, (a, m) => a + (m[b]?[s] ?? 0));

  num _oppoHari(String k, [String? s]) {
    final m = _oppo[k];
    if (m == null) return 0;
    return s == null ? m.values.fold<num>(0, (a, b) => a + b) : (m[s] ?? 0);
  }

  num _oppoTodate([String? s]) => _oppo.keys.fold<num>(0, (a, k) => a + _oppoHari(k, s));

  List<Map<String, dynamic>> _detail(String k) => [
        for (final e in (_data[k] ?? const <int, Map<String, int>>{}).entries)
          for (final s in _seg(e.key))
            if ((e.value[s] ?? 0) > 0) {'brand_id': e.key, 'segmen': s, 'unit': e.value[s]},
      ];

  // ---- simpan ---------------------------------------------------------
  void _set(int brand, String seg, int v) {
    setState(() {
      _hari(_key)[brand]![seg] = v < 0 ? 0 : v;
      _dirty = true;
      _perluNotif.add(_key);
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () => _simpan(_key, notif: false));
  }

  /// Simpan satu tanggal. notif=false: autosave diam-diam; notif=true: kabari atasan.
  Future<bool> _simpan(String k, {required bool notif}) async {
    if (k == _key) _debounce?.cancel();
    if (mounted) setState(() => _saving = true);
    final dirtyIni = k == _key && _dirty;
    if (k == _key) _dirty = false;
    try {
      await Session.db.rpc('simpan_ms_allbrand',
          params: {'p_store': t.storeId, 'p_tanggal': k, 'p_detail': _detail(k), 'p_notif': notif});
      if (notif) _perluNotif.remove(k);
      if (mounted) {
        setState(() {
          _terisi[k] = wibNow();
          _saveError = null;
        });
      }
      return true;
    } catch (e) {
      if (dirtyIni) _dirty = true;
      if (mounted) setState(() => _saveError = errMsg(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pindah(DateTime d) async {
    if (isSameDay(d, _tgl)) return;
    if (_dirty) await _simpan(_key, notif: false);
    if (!mounted) return;
    setState(() {
      _tgl = d;
      _saveError = null;
    });
  }

  Future<void> _pilihTanggal() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tgl,
      firstDate: _awal,
      lastDate: _akhir,
      helpText: 'Tanggal MS Allbrand',
    );
    if (d != null) _pindah(dateOnly(d));
  }

  Future<void> _selesai() async {
    final k = _key;
    if (_detail(k).isEmpty && !_terisi.containsKey(k)) {
      final ok = await confirmDialog(context, 'Semua brand 0?',
          'Simpan bahwa tanggal ${tglPendek(_tgl)} tidak ada penjualan brand lain di toko ini?', yes: 'Simpan');
      if (!ok) return;
    }
    // Tanggal terpilih + tanggal lain yang sudah diubah: simpan & kabari atasan
    final semua = {..._perluNotif, k};
    var ok = true;
    for (final x in semua) {
      ok = await _simpan(x, notif: true) && ok;
    }
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'MS Allbrand tersimpan');
      Navigator.pop(context, true);
    } else if (_saveError != null) {
      showMsg(context, _saveError!);
    }
  }

  Future<void> _hapus() async {
    final k = _key;
    final ok = await confirmDialog(context, 'Hapus MS Allbrand ${tglPendek(_tgl)}?',
        'Semua angka brand lain tanggal ini dihapus dan tanggal ini kembali "belum diisi".',
        yes: 'Hapus');
    if (!ok) return;
    _debounce?.cancel();
    setState(() => _saving = true);
    try {
      await Session.db.rpc('hapus_ms_allbrand', params: {'p_store': t.storeId, 'p_tanggal': k});
      if (!mounted) return;
      setState(() {
        _data.remove(k);
        _terisi.remove(k);
        _perluNotif.remove(k);
        _dirty = false;
        _saveError = null;
      });
      showMsg(context, 'MS Allbrand ${tglPendek(_tgl)} dihapus');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _ketik(int brand, String seg, String namaBrand) async {
    final c = TextEditingController(text: '${_hari(_key)[brand]![seg]}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$namaBrand · ${segmenLabel[seg]}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Terjual ${tglPendek(_tgl)}', suffixText: 'unit'),
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

  // ---- tampilan -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final boleh = _boleh(_tgl);
    final hariIni = isSameDay(_tgl, wibToday());
    final labelHari = hariIni ? 'Today' : 'Tgl ${_tgl.day}';
    final hari = _data[_key] ?? _kosong();
    final oppoHari = _oppoHari(_key);
    final lainHari = _total(hari);
    final oppoTd = _oppoTodate();
    final lainTd = _todateTotal();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MS Allbrand'),
          Text(t.toko, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          if (boleh && _terisi.containsKey(_key))
            IconButton(
              onPressed: _saving ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus MS tanggal ini',
            ),
        ],
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
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                  _pilihHari(),
                  if (!boleh)
                    const InfoBanner('Tanggal ini tidak bisa diubah (hanya tgl 1 s.d. hari ini di bulan berjalan).',
                        icon: Icons.lock_outline),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Table(
                        columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          _row('', labelHari, 'Todate', header: true),
                          _row('OPPO', angka(oppoHari), angka(oppoTd)),
                          _row('Brand lain', angka(lainHari), angka(lainTd)),
                          _row('MS OPPO', _ms(oppoHari, lainHari), _ms(oppoTd, lainTd), tebal: true),
                          for (final s in segmenList)
                            _row(
                              'MS ${segmenLabel[s]}',
                              _ms(_oppoHari(_key, s), _sumSeg(hari, s)),
                              _ms(_oppoTodate(s), _todateSeg(s)),
                              kecil: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Isi unit HP brand lain yang terjual pada tanggal terpilih. Tanggal yang sudah lewat tetap bisa '
                      'dipilih dan diedit. Isian tiap tanggal tersimpan otomatis dan tidak hilang kecuali dihapus '
                      '(ikon tempat sampah). Todate = jumlah tgl 1 s.d. hari ini.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final b in _brands) _brandCard(b, hari, boleh, labelHari),
                ]),
    );
  }

  /// Pilih tanggal: panah kiri/kanan, ketuk tanggal untuk kalender, dan deretan tanggal 1 s.d. hari ini.
  Widget _pilihHari() {
    final hariList = <DateTime>[
      for (var d = _awal; !d.isAfter(_akhir); d = addDays(d, 1)) d,
    ];
    final c = Theme.of(context).colorScheme.primary;
    final sebelum = addDays(_tgl, -1);
    final sesudah = addDays(_tgl, 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(children: [
          Row(children: [
            IconButton(
              onPressed: sebelum.isBefore(_awal) ? null : () => _pindah(sebelum),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: InkWell(
                onTap: _pilihTanggal,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.calendar_month, size: 18),
                    const SizedBox(width: 6),
                    Text(hariTgl(_tgl), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
            IconButton(
              onPressed: sesudah.isAfter(_akhir) ? null : () => _pindah(sesudah),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (final d in hariList.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _chipHari(d, c),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chipHari(DateTime d, Color c) {
    final k = ymd(d);
    final pilih = isSameDay(d, _tgl);
    final isi = _terisi.containsKey(k);
    final unit = _data[k] == null ? 0 : _total(_data[k]!);
    return InkWell(
      onTap: () => _pindah(d),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pilih ? c : (isi ? c.withValues(alpha: 0.12) : null),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: pilih || isi ? c : Colors.grey.shade300),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${d.day}', style: TextStyle(fontWeight: FontWeight.bold, color: pilih ? Colors.white : null)),
          Text(isi ? '$unit' : '-',
              style: TextStyle(fontSize: 11, color: pilih ? Colors.white : (isi ? c : Colors.grey))),
        ]),
      ),
    );
  }

  Widget _statusSimpan() {
    final s = Theme.of(context).textTheme.bodySmall;
    if (_saving) return Text('Menyimpan…', style: s);
    if (_saveError != null) {
      return Text('Gagal menyimpan: $_saveError', style: s?.copyWith(color: Colors.red.shade700));
    }
    if (_dirty) return Text('Perubahan belum tersimpan…', style: s);
    final w = _terisi[_key];
    if (w != null) {
      return Text('Tgl ${_tgl.day} tersimpan · terakhir ${tglPendek(w)} ${jamMenit(w)} WIB',
          style: s?.copyWith(color: Colors.green.shade700));
    }
    if (_terisi.containsKey(_key)) return Text('Tgl ${_tgl.day} sudah diisi', style: s);
    return Text('Tgl ${_tgl.day} belum diisi', style: s);
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

  Widget _brandCard(Map<String, dynamic> b, Map<int, Map<String, int>> hari, bool boleh, String labelHari) {
    final id = toNum(b['id']).toInt();
    final nama = '${b['nama']}';
    final unitHari = _sumBrand(hari, id);
    final todate = _todateBrand(id);
    final c = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Text('$labelHari $unitHari', style: TextStyle(fontWeight: FontWeight.bold, color: unitHari > 0 ? c : Colors.grey)),
            const SizedBox(width: 10),
            Text('Todate $todate', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ]),
          for (final s in _seg(id))
            Row(children: [
              Expanded(child: Text(segmenLabel[s]!)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh && (hari[id]?[s] ?? 0) > 0 ? () => _set(id, s, hari[id]![s]! - 1) : null,
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
                  child: Text('${hari[id]?[s] ?? 0}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: boleh ? () => _set(id, s, (hari[id]?[s] ?? 0) + 1) : null,
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
