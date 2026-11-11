import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Jenis kolom di form edit.
enum _Tipe { teks, angka, desimal, pilihan, centang }

class _F {
  final String key;
  final String label;
  final _Tipe tipe;
  final bool wajib;
  final List<(String, String)> pilihan; // (nilai, label)
  final String? bantuan;
  const _F(this.key, this.label, this.tipe, {this.wajib = false, this.pilihan = const [], this.bantuan});
}

const _metrikList = [
  ('unit_hp', 'Unit HP'),
  ('value_hp', 'Value HP (Rp)'),
  ('unit_fokus', 'Unit A7 Pro + Reno 16'),
  ('unit_a7_reno', 'Unit A7 Pro + semua Reno Series'),
  ('unit_iot', 'Unit IoT'),
  ('unit_produk', 'Unit produk tertentu (isi filter nama)'),
  ('cek_limit', 'Jumlah cek limit (filter = nama leasing)'),
];

const _lainLabel = {
  'hp_lt2': 'HP lain < 2 jt',
  'hp_2to3': 'HP lain 2-3 jt',
  'hp_gt3': 'HP lain > 3 jt',
  'hp_reno': 'HP lain Reno Series',
  'hp_find': 'HP lain Find Series',
  'iot_lain': 'IoT lain (tidak ada di daftar)',
};

/// Kelola KPI & insentif per area per bulan: UMR, tier, potongan gaji, bonus & denda,
/// insentif per produk HP & IoT. PIC semua area, TL & Trainer areanya sendiri.
class KpiScreen extends StatefulWidget {
  const KpiScreen({super.key});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> {
  Profile get me => Session.current!;
  List<Map<String, dynamic>> _areas = [];
  int? _area;
  DateTime _bulan = monthStart();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Data bulan terpilih
  bool _ada = false; // bulan ini punya aturan sendiri
  DateTime? _bulanAturan; // bulan aturan yang berlaku (bisa bulan sebelumnya)
  final _umr = TextEditingController();
  List<Map<String, dynamic>> _tier = [];
  List<Map<String, dynamic>> _potongan = [];
  List<Map<String, dynamic>> _aturan = [];
  List<Map<String, dynamic>> _produk = [];
  final Map<int, TextEditingController> _ins = {};
  final Map<String, TextEditingController> _lain = {};

  String get _b => ymd(_bulan);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _umr.dispose();
    for (final c in [..._ins.values, ..._lain.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _areas = asList(await Session.db.from('areas').select('id,nama').order('id'));
      if (!me.isPic) _areas = _areas.where((a) => toNum(a['id']).toInt() == me.areaId).toList();
      _area = _areas.isEmpty ? null : toNum(_areas.first['id']).toInt();
    } catch (e) {
      _error = errMsg(e);
    }
    await _load();
  }

  Future<void> _load() async {
    if (_area == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final a = _area!;
      final res = await Future.wait<dynamic>([
        db.from('gaji_area').select('bulan,umr').eq('area_id', a).lte('bulan', _b).order('bulan', ascending: false).limit(1),
        db.from('kpi_tier').select().eq('area_id', a).eq('bulan', _b).order('urutan').order('id'),
        db.from('kpi_potongan').select().eq('area_id', a).eq('bulan', _b).order('unit_min', ascending: false),
        db.from('kpi_aturan').select().eq('area_id', a).eq('bulan', _b).order('jenis').order('urutan').order('id'),
        db.from('products').select('id,tipe,nama,grup').eq('aktif', true).order('tipe').order('urutan').order('nama'),
        db.from('insentif_produk').select('product_id,nilai').eq('area_id', a).eq('bulan', _b),
        db.from('insentif_lain').select('kode,nilai').eq('area_id', a).eq('bulan', _b),
      ]);
      final g = asList(res[0]);
      _bulanAturan = g.isEmpty ? null : parseDate('${g.first['bulan']}');
      _ada = _bulanAturan != null && isSameDay(_bulanAturan!, _bulan);
      _umr.text = g.isEmpty ? '' : '${toNum(g.first['umr']).toInt()}';
      _tier = asList(res[1]);
      _potongan = asList(res[2]);
      _aturan = asList(res[3]);
      _produk = asList(res[4]);
      final ins = {for (final r in asList(res[5])) toNum(r['product_id']).toInt(): toNum(r['nilai']).toInt()};
      final lain = {for (final r in asList(res[6])) '${r['kode']}': toNum(r['nilai']).toInt()};
      for (final c in [..._ins.values, ..._lain.values]) {
        c.dispose();
      }
      _ins
        ..clear()
        ..addAll({for (final p in _produk) toNum(p['id']).toInt(): TextEditingController(text: '${ins[toNum(p['id']).toInt()] ?? 0}')});
      _lain
        ..clear()
        ..addAll({for (final k in _lainLabel.keys) k: TextEditingController(text: '${lain[k] ?? 0}')});
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _jalankan(Future<void> Function() aksi, String pesan) async {
    setState(() => _busy = true);
    try {
      await aksi();
      await _load();
      if (mounted) showMsg(context, pesan);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _salin() async {
    final dari = _bulanAturan;
    if (dari == null) return;
    final ok = await confirmDialog(context, 'Salin aturan ${namaBulan(dari)}?',
        'Semua aturan (UMR, tier, potongan, bonus, denda, insentif) ${namaBulan(dari)} disalin ke ${namaBulan(_bulan)} '
        'lalu bisa diubah. Aturan ${namaBulan(_bulan)} yang sudah ada akan diganti.',
        yes: 'Salin');
    if (!ok) return;
    await _jalankan(
      () => Session.db.rpc('salin_kpi', params: {'p_area': _area, 'p_dari': ymd(dari), 'p_ke': _b}),
      'Aturan ${namaBulan(_bulan)} siap diubah',
    );
  }

  void _gantiBulan(int n) {
    _bulan = DateTime(_bulan.year, _bulan.month + n, 1);
    _load();
  }

  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('KPI & insentif'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Gaji & tier'),
            Tab(text: 'Bonus & denda'),
            Tab(text: 'Insentif HP'),
            Tab(text: 'Insentif IoT'),
          ]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              if (_areas.length > 1)
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _area,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Area', isDense: true),
                    items: [
                      for (final a in _areas) DropdownMenuItem(value: toNum(a['id']).toInt(), child: Text('${a['nama']}')),
                    ],
                    onChanged: (v) {
                      _area = v;
                      _load();
                    },
                  ),
                )
              else
                Expanded(child: Text('Area ${_areas.isEmpty ? '-' : _areas.first['nama']}', style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => _gantiBulan(-1), icon: const Icon(Icons.chevron_left)),
              Text(namaBulan(_bulan), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => _gantiBulan(1), icon: const Icon(Icons.chevron_right)),
            ]),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorRetry(error: _error!, onRetry: _load)
                    : !_ada
                        ? _belumAda()
                        : TabBarView(children: [_tabGaji(), _tabAturan(), _tabInsentif('HP'), _tabInsentif('IOT')]),
          ),
        ]),
      ),
    );
  }

  Widget _belumAda() => ListView(padding: const EdgeInsets.all(16), children: [
        InfoBanner(
          _bulanAturan == null
              ? 'Area ini belum punya aturan KPI sama sekali. Jalankan tahap2a.sql di Supabase untuk data awal.'
              : '${namaBulan(_bulan)} belum punya aturan sendiri. Estimasi gaji bulan ini memakai aturan ${namaBulan(_bulanAturan!)}.',
          icon: Icons.info_outline,
        ),
        if (_bulanAturan != null)
          FilledButton.icon(
            onPressed: _busy ? null : _salin,
            icon: const Icon(Icons.copy_all),
            label: Text('Salin aturan ${namaBulan(_bulanAturan!)} ke ${namaBulan(_bulan)} untuk diubah'),
          ),
      ]);

  // ---------------------------- GAJI & TIER ---------------------------
  Widget _tabGaji() {
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      const SectionHeader('Basic salary (UMR area)'),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _umr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'UMR', prefixText: 'Rp ', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _jalankan(
                    () => Session.db.from('gaji_area').update({'umr': digitsOnly(_umr.text)}).eq('area_id', _area!).eq('bulan', _b),
                    'UMR tersimpan',
                  ),
          child: const Text('Simpan'),
        ),
      ]),
      SectionHeader('Tier (dicek dari atas)', trailing: IconButton(onPressed: _busy ? null : () => _editTier(), icon: const Icon(Icons.add))),
      const Text('Tier pertama yang syaratnya terpenuhi dipakai. Value = value HP bulan berjalan.', style: TextStyle(fontSize: 12)),
      for (final t in _tier)
        Card(
          margin: const EdgeInsets.only(top: 4),
          child: ListTile(
            title: Text('${t['urutan']}. ${t['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_syaratTier(t)),
            onTap: _busy ? null : () => _editTier(t),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _hapus('kpi_tier', t, '${t['nama']}')),
          ),
        ),
      SectionHeader('Potongan gaji pokok (unit HP)',
          trailing: IconButton(onPressed: _busy ? null : () => _editPotongan(), icon: const Icon(Icons.add))),
      const Text('Gaji pokok = UMR - potongan sesuai unit HP (kecuali tier dengan "gaji % UMR").', style: TextStyle(fontSize: 12)),
      for (final p in _potongan)
        Card(
          margin: const EdgeInsets.only(top: 4),
          child: ListTile(
            title: Text(p['unit_max'] == null ? '${p['unit_min']} unit ke atas' : '${p['unit_min']} - ${p['unit_max']} unit'),
            subtitle: Text(toNum(p['potongan']) == 0 ? 'UMR penuh' : 'Potongan ${rupiah(toNum(p['potongan']))}'),
            onTap: _busy ? null : () => _editPotongan(p),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _hapus('kpi_potongan', p, 'potongan ini')),
          ),
        ),
    ]);
  }

  String _syaratTier(Map<String, dynamic> t) {
    final s = <String>[];
    if (t['value_min'] != null) s.add('value ≥ ${rupiah(toNum(t['value_min']))}');
    if (t['value_max'] != null) s.add('value < ${rupiah(toNum(t['value_max']))}');
    if (t['unit_min'] != null) s.add('unit ≥ ${t['unit_min']}');
    s.add('insentif HP ${toNum(t['persen_insentif']).toStringAsFixed(0)}%');
    if (t['gaji_persen_umr'] != null) s.add('gaji = UMR x ${toNum(t['gaji_persen_umr']).toStringAsFixed(0)}%');
    return s.join(' · ');
  }

  Future<void> _editTier([Map<String, dynamic>? t]) async {
    final v = await _form(t == null ? 'Tier baru' : 'Ubah ${t['nama']}', const [
      _F('urutan', 'Urutan dicek', _Tipe.angka, wajib: true),
      _F('nama', 'Nama tier', _Tipe.teks, wajib: true),
      _F('value_min', 'Value HP minimal (Rp)', _Tipe.angka, bantuan: 'Kosongkan jika tanpa batas bawah'),
      _F('value_max', 'Value HP di bawah (Rp)', _Tipe.angka, bantuan: 'Kosongkan jika tanpa batas atas'),
      _F('unit_min', 'Unit HP minimal', _Tipe.angka, bantuan: 'Kosongkan jika tidak dicek'),
      _F('persen_insentif', 'Persen insentif HP (%)', _Tipe.desimal, wajib: true),
      _F('gaji_persen_umr', 'Gaji pokok = UMR x ... % (opsional)', _Tipe.desimal, bantuan: 'Isi hanya untuk tier seperti Tier 7 (UMR x 50%)'),
    ], t ?? {'urutan': _tier.length + 1, 'persen_insentif': 100});
    if (v == null) return;
    await _simpan('kpi_tier', t, v, 'Tier tersimpan');
  }

  Future<void> _editPotongan([Map<String, dynamic>? p]) async {
    final v = await _form(p == null ? 'Potongan baru' : 'Ubah potongan', const [
      _F('unit_min', 'Unit HP dari', _Tipe.angka, wajib: true),
      _F('unit_max', 'Unit HP sampai', _Tipe.angka, bantuan: 'Kosongkan jika ke atas'),
      _F('potongan', 'Potongan dari UMR (Rp)', _Tipe.angka, wajib: true, bantuan: '0 = UMR penuh'),
    ], p ?? {'potongan': 0});
    if (v == null) return;
    await _simpan('kpi_potongan', p, v, 'Potongan tersimpan');
  }

  // ---------------------------- BONUS & DENDA -------------------------
  Widget _tabAturan() {
    final bonus = _aturan.where((a) => a['jenis'] == 'bonus').toList();
    final denda = _aturan.where((a) => a['jenis'] == 'denda').toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      SectionHeader('Bonus', trailing: IconButton(onPressed: _busy ? null : () => _editAturan(null, 'bonus'), icon: const Icon(Icons.add))),
      const Text('Berlaku jika pencapaian di antara batas minimal dan maksimal. Bonus dengan grup sama: ambil yang terbesar.',
          style: TextStyle(fontSize: 12)),
      for (final a in bonus) _aturanTile(a),
      SectionHeader('Denda', trailing: IconButton(onPressed: _busy ? null : () => _editAturan(null, 'denda'), icon: const Icon(Icons.add))),
      const Text('Berlaku jika pencapaian di bawah batas minimal. "Per unit" = nilai x kekurangan.', style: TextStyle(fontSize: 12)),
      for (final a in denda) _aturanTile(a),
    ]);
  }

  Widget _aturanTile(Map<String, dynamic> a) {
    final metrik = _metrikList.firstWhere((m) => m.$1 == a['metrik'], orElse: () => ('', '${a['metrik']}')).$2;
    final batas = a['batas_max'] == null ? '≥ ${_angka(a['batas_min'])}' : '${_angka(a['batas_min'])} - ${_angka(a['batas_max'])}';
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: ListTile(
        title: Text('${a['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          metrik + (a['filter'] != null ? ' "${a['filter']}"' : ''),
          a['jenis'] == 'bonus' ? batas : 'target ${_angka(a['batas_min'])}',
          '${rupiah(toNum(a['nilai']))}${a['per_unit'] == true ? (a['jenis'] == 'bonus' ? '/unit' : '/kekurangan') : ''}',
          if (a['grup'] != null) 'grup ${a['grup']}',
        ].join(' · ')),
        onTap: _busy ? null : () => _editAturan(a, '${a['jenis']}'),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _hapus('kpi_aturan', a, '${a['nama']}')),
      ),
    );
  }

  static String _angka(dynamic v) => v == null ? '-' : angka(toNum(v));

  Future<void> _editAturan(Map<String, dynamic>? a, String jenis) async {
    final v = await _form(a == null ? (jenis == 'bonus' ? 'Bonus baru' : 'Denda baru') : 'Ubah ${a['nama']}', [
      const _F('nama', 'Nama', _Tipe.teks, wajib: true),
      const _F('metrik', 'Dihitung dari', _Tipe.pilihan, wajib: true, pilihan: _metrikList),
      const _F('filter', 'Filter (nama produk / leasing)', _Tipe.teks, bantuan: 'Contoh: Air5 atau Avanto'),
      _F('batas_min', jenis == 'bonus' ? 'Batas minimal' : 'Target minimal', _Tipe.desimal, wajib: true),
      if (jenis == 'bonus') const _F('batas_max', 'Batas maksimal', _Tipe.desimal, bantuan: 'Kosongkan jika ke atas'),
      const _F('nilai', 'Nilai (Rp)', _Tipe.angka, wajib: true),
      _F('per_unit', jenis == 'bonus' ? 'Dikali jumlah unit' : 'Dikali kekurangan', _Tipe.centang),
      if (jenis == 'bonus') const _F('grup', 'Grup (opsional)', _Tipe.teks, bantuan: 'Bonus dengan grup sama: hanya yang terbesar'),
      const _F('urutan', 'Urutan tampil', _Tipe.angka),
    ], a ?? {'metrik': 'unit_hp', 'batas_min': jenis == 'denda' ? 1 : 0, 'per_unit': false, 'urutan': _aturan.length + 1});
    if (v == null) return;
    v['jenis'] = jenis;
    await _simpan('kpi_aturan', a, v, jenis == 'bonus' ? 'Bonus tersimpan' : 'Denda tersimpan');
  }

  // ---------------------------- INSENTIF ------------------------------
  Widget _tabInsentif(String tipe) {
    final list = _produk.where((p) => p['tipe'] == tipe).toList();
    final kodeLain = tipe == 'HP' ? ['hp_lt2', 'hp_2to3', 'hp_gt3', 'hp_reno', 'hp_find'] : ['iot_lain'];
    String? grup;
    final rows = <Widget>[];
    for (final p in list) {
      if (p['grup'] != grup) {
        grup = '${p['grup']}';
        rows.add(SectionHeader(grup));
      }
      rows.add(_nilaiRow('${p['nama']}', _ins[toNum(p['id']).toInt()]!));
    }
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
          Text('Insentif per unit ${tipe == 'HP' ? 'HP (dikali persen tier)' : 'IoT (dibayar 100%)'}. Ubah angka lalu tekan Simpan.',
              style: const TextStyle(fontSize: 12)),
          ...rows,
          const SectionHeader('Produk lain (tidak ada di daftar)'),
          for (final k in kodeLain) _nilaiRow(_lainLabel[k]!, _lain[k]!),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _simpanInsentif(list, kodeLain),
            icon: const Icon(Icons.save),
            label: Text('Simpan insentif ${tipe == 'HP' ? 'HP' : 'IoT'}'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    ]);
  }

  Widget _nilaiRow(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 120,
            child: TextField(
              controller: c,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(isDense: true, prefixText: 'Rp '),
            ),
          ),
        ]),
      );

  Future<void> _simpanInsentif(List<Map<String, dynamic>> list, List<String> kodeLain) => _jalankan(() async {
        final db = Session.db;
        await db.from('insentif_produk').upsert([
          for (final p in list)
            {'area_id': _area, 'bulan': _b, 'product_id': p['id'], 'nilai': digitsOnly(_ins[toNum(p['id']).toInt()]!.text)},
        ], onConflict: 'area_id,bulan,product_id');
        await db.from('insentif_lain').upsert([
          for (final k in kodeLain) {'area_id': _area, 'bulan': _b, 'kode': k, 'nilai': digitsOnly(_lain[k]!.text)},
        ], onConflict: 'area_id,bulan,kode');
      }, 'Insentif tersimpan');

  // ---------------------------- UMUM ----------------------------------
  Future<void> _simpan(String tabel, Map<String, dynamic>? lama, Map<String, dynamic> v, String pesan) => _jalankan(() async {
        if (lama == null) {
          await Session.db.from(tabel).insert({...v, 'area_id': _area, 'bulan': _b});
        } else {
          await Session.db.from(tabel).update(v).eq('id', toNum(lama['id']).toInt());
        }
      }, pesan);

  Future<void> _hapus(String tabel, Map<String, dynamic> r, String nama) async {
    final ok = await confirmDialog(context, 'Hapus $nama?', 'Aturan ini dihapus dari ${namaBulan(_bulan)}.', yes: 'Hapus');
    if (!ok) return;
    await _jalankan(() => Session.db.from(tabel).delete().eq('id', toNum(r['id']).toInt()), '$nama dihapus');
  }

  /// Form edit generik. Mengembalikan nilai baru (angka kosong = null) atau null jika batal.
  Future<Map<String, dynamic>?> _form(String judul, List<_F> fields, Map<String, dynamic> awal) async {
    final c = <String, TextEditingController>{};
    final pilih = <String, String?>{};
    final centang = <String, bool>{};
    for (final f in fields) {
      final x = awal[f.key];
      switch (f.tipe) {
        case _Tipe.pilihan:
          pilih[f.key] = x?.toString();
        case _Tipe.centang:
          centang[f.key] = x == true;
        case _Tipe.angka:
          c[f.key] = TextEditingController(text: x == null ? '' : '${toNum(x).toInt()}');
        case _Tipe.desimal:
          c[f.key] = TextEditingController(text: x == null ? '' : '${toNum(x) % 1 == 0 ? toNum(x).toInt() : toNum(x)}');
        case _Tipe.teks:
          c[f.key] = TextEditingController(text: x == null ? '' : '$x');
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(judul),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: switch (f.tipe) {
                    _Tipe.pilihan => DropdownButtonFormField<String>(
                        initialValue: pilih[f.key],
                        isExpanded: true,
                        decoration: InputDecoration(labelText: f.label, isDense: true),
                        items: [for (final o in f.pilihan) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setD(() => pilih[f.key] = v),
                      ),
                    _Tipe.centang => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: centang[f.key] ?? false,
                        title: Text(f.label),
                        onChanged: (v) => setD(() => centang[f.key] = v ?? false),
                      ),
                    _ => TextField(
                        controller: c[f.key],
                        keyboardType: f.tipe == _Tipe.teks ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: f.label + (f.wajib ? ' *' : ''), helperText: f.bantuan, isDense: true),
                      ),
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final out = <String, dynamic>{};
    String? kurang;
    for (final f in fields) {
      switch (f.tipe) {
        case _Tipe.pilihan:
          out[f.key] = pilih[f.key];
        case _Tipe.centang:
          out[f.key] = centang[f.key] ?? false;
        case _Tipe.teks:
          final s = c[f.key]!.text.trim();
          out[f.key] = s.isEmpty ? null : s;
        case _Tipe.angka:
          final s = c[f.key]!.text.trim();
          out[f.key] = s.isEmpty ? null : digitsOnly(s);
        case _Tipe.desimal:
          final s = c[f.key]!.text.trim().replaceAll(',', '.');
          out[f.key] = s.isEmpty ? null : num.tryParse(s);
      }
      if (f.wajib && out[f.key] == null) kurang ??= f.label;
    }
    for (final x in c.values) {
      x.dispose();
    }
    if (ok != true) return null;
    if (kurang != null) {
      if (mounted) showMsg(context, '$kurang wajib diisi');
      return null;
    }
    return out;
  }
}
