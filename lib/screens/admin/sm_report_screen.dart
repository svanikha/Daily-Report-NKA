import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../pc/sale_form.dart';

/// Daily Report Store Manager: 1 kesimpulan per toko.
/// Revenue, konten MKT, A7 Pro dan database promotor diambil otomatis;
/// customer served, bundling IoT, kopi, antigores dan database SM diisi manual.
class SmReportScreen extends StatefulWidget {
  const SmReportScreen({super.key});

  @override
  State<SmReportScreen> createState() => _SmReportScreenState();
}

class _SmReportScreenState extends State<SmReportScreen> {
  DateTime _tanggal = wibToday();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Data otomatis dari promotor
  num _revHari = 0, _revBulan = 0, _revTarget = 0;
  num _kontenHari = 0, _kontenBulan = 0;
  num _a7Hari = 0, _a7Bulan = 0;
  num _dbPcHari = 0, _dbPcBulan = 0;

  // Total input SM bulan ini SEBELUM tanggal laporan
  num _dbSmSebelum = 0;

  List<Map<String, dynamic>> _pcs = [];
  List<Map<String, dynamic>> _salesHari = [];

  final _cust = TextEditingController();
  final _bundling = TextEditingController();
  final _kopi = TextEditingController();
  final _antigores = TextEditingController();
  final _dbSm = TextEditingController();
  final _kontenSm = TextEditingController();
  // Total bulan ini (terpisah dari hari ini): otomatis = total kemarin + hari ini, bisa diubah manual.
  final _custTotal = TextEditingController();
  final _agTotal = TextEditingController();
  final _kopiTotal = TextEditingController();
  final _kontenSmTotal = TextEditingController();
  num _custBase = 0, _agBase = 0, _kopiBase = 0, _kontenSmBase = 0;
  bool _custTotalManual = false, _agTotalManual = false, _kopiTotalManual = false, _kontenSmTotalManual = false;
  final _targetA7 = TextEditingController();

  int get _storeId => Session.current!.storeId!;
  String get _toko => (Session.current?.toko ?? '').toUpperCase();

  @override
  void initState() {
    super.initState();
    for (final c in [_cust, _bundling, _kopi, _antigores, _dbSm, _kontenSm, _targetA7, _custTotal, _agTotal, _kopiTotal, _kontenSmTotal]) {
      c.addListener(() => setState(() {}));
    }
    // Total bulan ini ikut berubah saat angka hari ini diisi, selama belum diubah manual.
    _cust.addListener(() {
      if (!_custTotalManual) _custTotal.text = '${_custBase + _val(_cust)}';
    });
    _antigores.addListener(() {
      if (!_agTotalManual) _agTotal.text = '${_agBase + _val(_antigores)}';
    });
    _kopi.addListener(() {
      if (!_kopiTotalManual) _kopiTotal.text = '${_kopiBase + _val(_kopi)}';
    });
    _kontenSm.addListener(() {
      if (!_kontenSmTotalManual) _kontenSmTotal.text = '${_kontenSmBase + _val(_kontenSm)}';
    });
    _load();
  }

  @override
  void dispose() {
    for (final c in [_cust, _bundling, _kopi, _antigores, _dbSm, _kontenSm, _targetA7, _custTotal, _agTotal, _kopiTotal, _kontenSmTotal]) {
      c.dispose();
    }
    super.dispose();
  }

  static bool _isA7Pro(Map<String, dynamic> s) {
    final n = '${s['nama_produk']}'.toUpperCase().replaceAll(' ', '');
    return n.startsWith('A7PRO') && !n.contains('MAX');
  }

  static String _int(TextEditingController c) => c.text.trim();
  static num _val(TextEditingController c) => digitsOnly(c.text);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final ds = ymd(_tanggal);
      final ms = ymd(monthStart(_tanggal));
      final pcs = asList(await db.from('profiles').select('id,nama,email,store_id').eq('store_id', _storeId).eq('role', 'pc').eq('aktif', true).order('nama'));
      _pcs = pcs;
      final ids = pcs.map((p) => p['id'] as String).toList();
      final dariUtc = wibToUtcIso(monthStart(_tanggal));
      final besokUtc = wibToUtcIso(addDays(_tanggal, 1));

      final res = await Future.wait<dynamic>([
        ids.isEmpty
            ? Future.value([])
            : db.from('sales').select('id,pc_id,tanggal,tipe,nama_produk,qty,subtotal,created_at').inFilter('pc_id', ids).gte('tanggal', ms).lte('tanggal', ds),
        ids.isEmpty
            ? Future.value([])
            : db.from('social_activities').select('tanggal,jumlah')
                .inFilter('pc_id', ids)
                .eq('kode', 'tiktok_konten') // hanya konten TikTok promotor
                .gte('tanggal', ms)
                .lte('tanggal', ds),
        ids.isEmpty
            ? Future.value([])
            : db.from('contacts').select('created_at').inFilter('pc_id', ids).gte('created_at', dariUtc).lt('created_at', besokUtc),
        ids.isEmpty
            ? Future.value([])
            : db.from('targets').select('nilai').inFilter('pc_id', ids).eq('bulan', ms).eq('jenis', 'revenue_hp'),
        db.from('sm_reports').select().eq('store_id', _storeId).gte('tanggal', ms).lte('tanggal', ds),
        db.from('store_targets').select('nilai').eq('store_id', _storeId).eq('bulan', ms).eq('jenis', 'a7pro_unit'),
      ]);

      final sales = asList(res[0]);
      final hp = sales.where((s) => s['tipe'] == 'HP');
      _revBulan = hp.fold<num>(0, (a, s) => a + toNum(s['subtotal']));
      _revHari = hp.where((s) => s['tanggal'] == ds).fold<num>(0, (a, s) => a + toNum(s['subtotal']));
      final a7 = hp.where(_isA7Pro);
      _a7Bulan = a7.fold<num>(0, (a, s) => a + toNum(s['qty']));
      _a7Hari = a7.where((s) => s['tanggal'] == ds).fold<num>(0, (a, s) => a + toNum(s['qty']));

      final sos = asList(res[1]);
      _kontenBulan = sos.fold<num>(0, (a, s) => a + toNum(s['jumlah']));
      _kontenHari = sos.where((s) => s['tanggal'] == ds).fold<num>(0, (a, s) => a + toNum(s['jumlah']));

      final kontak = asList(res[2]);
      _dbPcBulan = kontak.length;
      _dbPcHari = kontak.where((c) => isSameDay(parseWib('${c['created_at']}'), _tanggal)).length;

      _revTarget = asList(res[3]).fold<num>(0, (a, t) => a + toNum(t['nilai']));

      final sm = asList(res[4]);
      final sebelum = sm.where((r) => r['tanggal'] != ds);
      num sum(String k) => sebelum.fold<num>(0, (a, r) => a + toNum(r[k]));
      _dbSmSebelum = sum('database_sm');
      // Total s.d. kemarin: pakai total terakhir yang diisi SM, ditambah angka harian setelahnya.
      num base(String harian, String total) {
        final rows = sebelum.toList()..sort((a, b) => '${a['tanggal']}'.compareTo('${b['tanggal']}'));
        num acc = 0;
        for (final r in rows) {
          acc = r[total] != null ? toNum(r[total]) : acc + toNum(r[harian]);
        }
        return acc;
      }

      _custBase = base('cust_served', 'cust_total');
      _agBase = base('antigores', 'antigores_total');
      _kopiBase = base('kopi', 'kopi_total');
      _kontenSmBase = base('konten_sm', 'konten_sm_total');
      _salesHari = sales.where((s) => s['tanggal'] == ds).toList()
        ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));

      final hariIni = sm.where((r) => r['tanggal'] == ds).firstOrNull;
      String s(dynamic v) => v == null ? '' : '${toNum(v) % 1 == 0 ? toNum(v).toInt() : toNum(v)}';
      _cust.text = s(hariIni?['cust_served']);
      _bundling.text = s(hariIni?['bundling_iot']);
      _kopi.text = s(hariIni?['kopi']);
      _antigores.text = s(hariIni?['antigores']);
      _dbSm.text = s(hariIni?['database_sm']);
      _kontenSm.text = s(hariIni?['konten_sm']);
      _custTotalManual = hariIni?['cust_total'] != null;
      _agTotalManual = hariIni?['antigores_total'] != null;
      _custTotal.text = _custTotalManual ? s(hariIni!['cust_total']) : '${_custBase + _val(_cust)}';
      _agTotal.text = _agTotalManual ? s(hariIni!['antigores_total']) : '${_agBase + _val(_antigores)}';
      _kopiTotalManual = hariIni?['kopi_total'] != null;
      _kontenSmTotalManual = hariIni?['konten_sm_total'] != null;
      _kopiTotal.text = _kopiTotalManual ? s(hariIni!['kopi_total']) : '${_kopiBase + _val(_kopi)}';
      _kontenSmTotal.text =
          _kontenSmTotalManual ? s(hariIni!['konten_sm_total']) : '${_kontenSmBase + _val(_kontenSm)}';
      final ta = asList(res[5]);
      _targetA7.text = ta.isEmpty ? '' : s(ta.first['nilai']);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  static final _pctFmt = NumberFormat('#,##0.##', 'id_ID');
  String _pct(num a, num t) => t <= 0 ? '-' : '${_pctFmt.format(a / t * 100)}%';

  num get _bundlingVal => num.tryParse(_bundling.text.trim().replaceAll(',', '.').replaceAll('%', '')) ?? 0;

  String get _text {
    final cust = _val(_cust), kopi = _val(_kopi), ag = _val(_antigores), dbSm = _val(_dbSm), tA7 = _val(_targetA7);
    final kSm = _val(_kontenSm);
    final dbHari = _dbPcHari + dbSm;
    final dbTotal = _dbPcBulan + _dbSmSebelum + dbSm;
    return [
      'Daily Report SM : $_toko',
      'Tanggal : ${DateFormat('dd/MM/yyyy').format(_tanggal)}',
      '',
      'Revenue: ${angka(_revHari)} / ${angka(_revBulan)} / ${angka(_revTarget)} / ${_pct(_revBulan, _revTarget)}',
      'Cust. Served: ${angka(cust)}, Total Cust. Served: ${angka(_val(_custTotal))}',
      'Konten MKT: ${angka(_kontenHari + kSm)}, Total Konten MKT: ${angka(_kontenBulan + _val(_kontenSmTotal))}',
      'Bundling Rate IOT: ${_pctFmt.format(_bundlingVal)}%',
      'A7PRO: ${angka(_a7Hari)} / ${angka(_a7Bulan)} / ${angka(tA7)} / ${_pct(_a7Bulan, tA7)}',
      'Jmlh Cup Kopi: ${angka(kopi)}/${angka(_val(_kopiTotal))}',
      'Free Antigores: ${angka(ag)}/${angka(_val(_agTotal))}',
      'Database: ${angka(dbHari)}/${angka(dbTotal)}',
    ].join('\n');
  }

  String? _validate() {
    if (_int(_cust).isEmpty) return 'Isi Customer Served hari ini';
    if (_val(_custTotal) < _val(_cust)) return 'Total Customer Served bulan ini tidak boleh lebih kecil dari hari ini';
    if (_val(_agTotal) < _val(_antigores)) return 'Total Free Antigores bulan ini tidak boleh lebih kecil dari hari ini';
    if (_val(_kopiTotal) < _val(_kopi)) return 'Total Cup Kopi bulan ini tidak boleh lebih kecil dari hari ini';
    if (_val(_kontenSmTotal) < _val(_kontenSm)) return 'Total Konten SM bulan ini tidak boleh lebih kecil dari hari ini';
    if (_bundling.text.trim().isEmpty) return 'Isi Bundling Rate IoT (%)';
    if (_bundlingVal < 0 || _bundlingVal > 100) return 'Bundling Rate IoT harus 0 sampai 100%';
    return null;
  }

  Future<bool> _save() async {
    final err = _validate();
    if (err != null) {
      showMsg(context, err);
      return false;
    }
    setState(() => _saving = true);
    try {
      final db = Session.db;
      final me = Session.current!.id;
      await db.from('sm_reports').upsert({
        'store_id': _storeId,
        'tanggal': ymd(_tanggal),
        'cust_served': _val(_cust),
        'bundling_iot': _bundlingVal,
        'kopi': _val(_kopi),
        'antigores': _val(_antigores),
        'cust_total': _val(_custTotal),
        'antigores_total': _val(_agTotal),
        'kopi_total': _val(_kopiTotal),
        'konten_sm_total': _val(_kontenSmTotal),
        'database_sm': _val(_dbSm),
        'konten_sm': _val(_kontenSm),
        'updated_by': me,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'store_id,tanggal');
      if (_targetA7.text.trim().isNotEmpty) {
        await db.from('store_targets').upsert({
          'store_id': _storeId,
          'bulan': ymd(monthStart(_tanggal)),
          'jenis': 'a7pro_unit',
          'nilai': _val(_targetA7),
          'updated_by': me,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'store_id,bulan,jenis');
      }
      if (mounted) setState(() => _saving = false);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErr(context, e);
      }
      return false;
    }
  }

  Future<void> _share() async {
    if (!await _save()) return;
    try {
      await SharePlus.instance.share(ShareParams(text: _text));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _copy() async {
    if (!await _save()) return;
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) showMsg(context, 'Report disimpan & disalin. Tempel di grup WhatsApp.');
  }

  /// Muat ulang data promotor tanpa menghapus isian SM yang belum disimpan.
  Future<void> _reloadKeepInputs() async {
    final ctrls = [_cust, _bundling, _kopi, _antigores, _dbSm, _kontenSm, _targetA7, _custTotal, _agTotal, _kopiTotal, _kontenSmTotal];
    final saved = ctrls.map((c) => c.text).toList();
    final manual = [_custTotalManual, _agTotalManual, _kopiTotalManual, _kontenSmTotalManual];
    await _load();
    _custTotalManual = manual[0];
    _agTotalManual = manual[1];
    _kopiTotalManual = manual[2];
    _kontenSmTotalManual = manual[3];
    for (var i = 0; i < ctrls.length; i++) {
      ctrls[i].text = saved[i];
    }
  }

  String _namaPc(dynamic id) => '${_pcs.where((p) => p['id'] == id).firstOrNull?['nama'] ?? '-'}';

  /// SM menginput penjualan atas nama promotor yang berjualan.
  Future<void> _addSale(String tipe) async {
    if (_pcs.isEmpty) {
      showMsg(context, 'Belum ada promotor aktif di toko ini');
      return;
    }
    final pc = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('Penjualan ${tipe == 'HP' ? 'HP' : 'IoT'}: pilih promotor yang berjualan',
              style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final p in _pcs)
            ListTile(leading: const Icon(Icons.person), title: Text('${p['nama']}'), onTap: () => Navigator.pop(ctx, p)),
        ]),
      ),
    );
    if (pc == null || !mounted) return;
    final profile = Profile.fromMap({...pc, 'role': 'pc', 'toko': Session.current?.toko ?? ''});
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SaleForm(pc: profile, tipe: tipe, tanggal: _tanggal)),
    );
    if (ok == true) await _reloadKeepInputs();
  }

  Future<void> _deleteSale(Map<String, dynamic> s) async {
    final ok = await confirmDialog(context, 'Hapus penjualan?',
        '${s['nama_produk']} x${s['qty']} (${_namaPc(s['pc_id'])}) akan dihapus.', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('sales').delete().eq('id', s['id']);
      await _reloadKeepInputs();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2024),
      lastDate: wibToday(),
      helpText: 'Tanggal report',
    );
    if (d != null) {
      _tanggal = dateOnly(d);
      _load();
    }
  }

  Widget _field(TextEditingController c, String label, {String? helper, bool decimal = false, String? suffix}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))],
          decoration: InputDecoration(labelText: label, helperText: helper, suffixText: suffix, isDense: true),
        ),
      );

  /// Input "hari ini" dan "total bulan ini" berdampingan (terpisah).
  Widget _pair(
    TextEditingController harian,
    String labelHarian,
    TextEditingController total,
    String labelTotal, {
    required num base,
    required bool manual,
    required ValueChanged<bool> onManual,
    required TextEditingController hariIni,
  }) {
    final otomatis = base + _val(hariIni);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _field(harian, labelHarian)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: total,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onManual(true),
                  decoration: InputDecoration(labelText: labelTotal, isDense: true),
                ),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: Text(
                manual
                    ? 'Total diisi manual'
                    : 'Total otomatis: s.d. kemarin ${angka(base)} + hari ini ${angka(_val(hariIni))}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            if (manual && _val(total) != otomatis)
              TextButton(
                onPressed: () {
                  onManual(false);
                  total.text = '$otomatis';
                },
                child: Text('Pakai otomatis (${angka(otomatis)})', style: const TextStyle(fontSize: 11)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _auto(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report SM'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(hariTgl(_tanggal)),
                    subtitle: Text(_toko),
                    trailing: TextButton(onPressed: _pickDate, child: const Text('Ganti tanggal')),
                  ),
                  const SectionHeader('Otomatis dari promotor'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        _auto('Revenue HP hari ini', rupiah(_revHari)),
                        _auto('Revenue HP bulan ini', rupiah(_revBulan)),
                        _auto('Target revenue HP toko', rupiah(_revTarget)),
                        _auto('Konten TikTok promotor hari ini / bulan ini', '${angka(_kontenHari)} / ${angka(_kontenBulan)}'),
                        _auto('A7 Pro hari ini / bulan ini', '${angka(_a7Hari)} / ${angka(_a7Bulan)} unit'),
                        _auto('Database promotor hari ini / bulan ini', '${angka(_dbPcHari)} / ${angka(_dbPcBulan)}'),
                      ]),
                    ),
                  ),
                  SectionHeader('Penjualan ${tglPendek(_tanggal)}'),
                  const InfoBanner('Jika promotor offday atau lupa, Store Manager bisa input penjualan atas nama promotor yang berjualan.',
                      icon: Icons.point_of_sale),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addSale('HP'),
                        icon: const Icon(Icons.smartphone),
                        label: const Text('+ Penjualan HP'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addSale('IOT'),
                        icon: const Icon(Icons.watch),
                        label: const Text('+ Penjualan IoT'),
                      ),
                    ),
                  ]),
                  if (_salesHari.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Belum ada penjualan di tanggal ini', style: TextStyle(color: Colors.grey)),
                    ),
                  for (final s in _salesHari)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(s['tipe'] == 'HP' ? Icons.smartphone : Icons.watch, size: 20),
                      title: Text('${s['nama_produk']} x${s['qty']}'),
                      subtitle: Text('${_namaPc(s['pc_id'])} · ${rupiah(toNum(s['subtotal']))}'),
                      trailing: IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteSale(s),
                      ),
                    ),
                  const SectionHeader('Diisi Store Manager'),
                  _pair(
                    _kontenSm,
                    'Konten MKT dari SM hari ini',
                    _kontenSmTotal,
                    'Total konten SM bulan ini',
                    base: _kontenSmBase,
                    manual: _kontenSmTotalManual,
                    onManual: (v) => setState(() => _kontenSmTotalManual = v),
                    hariIni: _kontenSm,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 4),
                    child: Text(
                      'Konten MKT di report = SM + konten TikTok promotor. '
                      'Hari ini: ${angka(_val(_kontenSm))} + ${angka(_kontenHari)} = ${angka(_val(_kontenSm) + _kontenHari)} · '
                      'Total: ${angka(_val(_kontenSmTotal))} + ${angka(_kontenBulan)} = ${angka(_val(_kontenSmTotal) + _kontenBulan)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  _pair(
                    _cust,
                    'Customer Served hari ini *',
                    _custTotal,
                    'Total Customer Served bulan ini',
                    base: _custBase,
                    manual: _custTotalManual,
                    onManual: (v) => setState(() => _custTotalManual = v),
                    hariIni: _cust,
                  ),
                  _field(_bundling, 'Bundling Rate IoT *', decimal: true, suffix: '%'),
                  _pair(
                    _kopi,
                    'Cup kopi hari ini',
                    _kopiTotal,
                    'Total cup kopi bulan ini',
                    base: _kopiBase,
                    manual: _kopiTotalManual,
                    onManual: (v) => setState(() => _kopiTotalManual = v),
                    hariIni: _kopi,
                  ),
                  _pair(
                    _antigores,
                    'Free Antigores hari ini',
                    _agTotal,
                    'Total Free Antigores bulan ini',
                    base: _agBase,
                    manual: _agTotalManual,
                    onManual: (v) => setState(() => _agTotalManual = v),
                    hariIni: _antigores,
                  ),
                  _field(_dbSm, 'Database tambahan dari SM hari ini',
                      helper: 'Di luar database yang diinput promotor. Total SM bulan ini: ${angka(_dbSmSebelum + _val(_dbSm))}'),
                  _field(_targetA7, 'Target A7 Pro bulan ini', suffix: 'unit', helper: 'Cukup diisi sekali per bulan'),
                  const SectionHeader('Pratinjau report'),
                  Card(
                    color: const Color(0xFFF1F8F4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(_text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _share,
                    icon: busyIcon(_saving, Icons.share),
                    label: const Text('Simpan & bagikan ke WhatsApp'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Simpan & salin teks'),
                  ),
                ]),
    );
  }
}
