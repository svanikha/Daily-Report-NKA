import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Nama tipe tanpa varian RAM/ROM: "A6X [4/64]" -> "A6X".
String namaTipe(String nama) {
  final i = nama.indexOf(' [');
  return i > 0 ? nama.substring(0, i).trim() : nama.trim();
}

/// Varian RAM/ROM: "A6X [4/64]" -> "4/64" (kosong jika tidak ada).
String namaVarian(String nama) {
  final a = nama.indexOf('[');
  final b = nama.indexOf(']');
  return a >= 0 && b > a ? nama.substring(a + 1, b) : '';
}

/// Urutan series HP.
int urutanGrup(String g) => switch (g) {
      'A Series' => 1,
      'Reno Series' => 2,
      'Find Series' => 3,
      _ => 9,
    };

const _warnaGrup = {
  'A Series': Color(0xFF2E7D32),
  'Reno Series': Color(0xFF1565C0),
  'Find Series': Color(0xFF6A1B9A),
};

Color warnaGrup(String g) => _warnaGrup[g] ?? const Color(0xFFEF6C00);

/// Kontribusi penjualan bulan berjalan per series (A / Reno / Find) dan per tipe.
/// storeId null = semua toko di cakupan akun (atasan).
class KontribusiTipe extends StatefulWidget {
  final int? storeId;
  final DateTime tanggal;
  const KontribusiTipe({super.key, required this.storeId, required this.tanggal});

  @override
  State<KontribusiTipe> createState() => _KontribusiTipeState();
}

class _KontribusiTipeState extends State<KontribusiTipe> {
  List<Map<String, dynamic>>? _rows;
  bool _iot = false;
  final Set<String> _buka = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KontribusiTipe old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId || !isSameDay(old.tanggal, widget.tanggal)) _load();
  }

  Future<void> _load() async {
    try {
      final r = asList(await Session.db
          .rpc('kontribusi_tipe', params: {'p_store': widget.storeId, 'p_tanggal': ymd(widget.tanggal)}));
      if (mounted) setState(() => _rows = r);
    } catch (_) {
      // Fungsi kontribusi_tipe belum ada di server (tahap2f.sql): kartu disembunyikan.
      if (mounted) setState(() => _rows = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    final list = rows.where((r) => (r['tipe'] == 'IOT') == _iot).toList();
    final total = list.fold<num>(0, (a, r) => a + toNum(r['unit']));
    final totalValue = list.fold<num>(0, (a, r) => a + toNum(r['value']));

    // grup -> tipe -> [baris produk]
    final grup = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final r in list) {
      grup.putIfAbsent('${r['grup']}', () => {}).putIfAbsent(namaTipe('${r['nama']}'), () => []).add(r);
    }
    final grupUrut = grup.keys.toList()..sort((a, b) => urutanGrup(a).compareTo(urutanGrup(b)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.donut_large, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('KONTRIBUSI TIPE · ${namaBulan(widget.tanggal).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('HP'), icon: Icon(Icons.smartphone)),
              ButtonSegment(value: true, label: Text('IoT'), icon: Icon(Icons.watch)),
            ],
            selected: {_iot},
            onSelectionChanged: (s) => setState(() => _iot = s.first),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada penjualan ${_iot ? 'IoT' : 'HP'} bulan ini', style: TextStyle(color: Colors.grey.shade600)),
            )
          else ...[
            Text('Total ${angka(total)} unit · ${rupiah(totalValue)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _barGabung(grupUrut, grup, total),
            const SizedBox(height: 6),
            for (final g in grupUrut) ..._grupRows(g, grup[g]!, total),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RiwayatPenjualanScreen(storeId: widget.storeId, tanggal: widget.tanggal),
              )),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Riwayat penjualan'),
            ),
          ),
        ]),
      ),
    );
  }

  /// Satu batang berwarna: porsi tiap series.
  Widget _barGabung(List<String> urut, Map<String, Map<String, List<Map<String, dynamic>>>> grup, num total) {
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 10,
        child: Row(children: [
          for (final g in urut)
            Expanded(
              flex: (_unitGrup(grup[g]!) * 1000 ~/ total).clamp(1, 1000),
              child: Container(color: warnaGrup(g)),
            ),
        ]),
      ),
    );
  }

  num _unitGrup(Map<String, List<Map<String, dynamic>>> tipe) =>
      tipe.values.expand((l) => l).fold<num>(0, (a, r) => a + toNum(r['unit']));

  List<Widget> _grupRows(String g, Map<String, List<Map<String, dynamic>>> tipe, num total) {
    final unit = _unitGrup(tipe);
    final value = tipe.values.expand((l) => l).fold<num>(0, (a, r) => a + toNum(r['value']));
    final c = warnaGrup(g);
    final buka = _buka.contains(g);
    num u(List<Map<String, dynamic>> l) => l.fold<num>(0, (x, r) => x + toNum(r['unit']));
    final tipeUrut = tipe.entries.toList()..sort((a, b) => u(b.value).compareTo(u(a.value)));
    return [
      InkWell(
        onTap: () => setState(() => buka ? _buka.remove(g) : _buka.add(g)),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(g, style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('${angka(unit)} unit', style: const TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(
              width: 48,
              child: Text(_pct(unit, total),
                  textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
            ),
            Icon(buka ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.grey),
          ]),
        ),
      ),
      if (buka)
        Container(
          margin: const EdgeInsets.only(left: 18, bottom: 6),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c.withValues(alpha: 0.4), width: 2))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Expanded(child: Text(rupiah(value), style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
              ]),
            ),
            for (final e in tipeUrut) _tipeRow(e.key, e.value, total, c),
          ]),
        ),
    ];
  }

  Widget _tipeRow(String tipe, List<Map<String, dynamic>> rows, num total, Color c) {
    final unit = rows.fold<num>(0, (a, r) => a + toNum(r['unit']));
    final hari = rows.fold<num>(0, (a, r) => a + toNum(r['unit_hari']));
    final varian = rows
        .where((r) => namaVarian('${r['nama']}').isNotEmpty)
        .map((r) => '${namaVarian('${r['nama']}')}: ${angka(toNum(r['unit']))}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tipe, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          if (hari > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('+${angka(hari)} hari ini', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
            ),
          Text(angka(unit), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          SizedBox(
            width: 44,
            child: Text(_pct(unit, total), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c)),
          ),
        ]),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: total > 0 ? (unit / total).toDouble() : 0,
            minHeight: 4,
            color: c,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
        if (varian.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(varian, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ),
      ]),
    );
  }

  String _pct(num v, num total) => total > 0 ? '${(v / total * 100).toStringAsFixed(0)}%' : '-';
}

/// Riwayat penjualan bulan tertentu, dikelompokkan per series lalu per tipe.
/// Setiap transaksi: tanggal, varian, qty, kategori user, dan cara bayar.
class RiwayatPenjualanScreen extends StatefulWidget {
  final int? storeId;
  final DateTime tanggal;
  const RiwayatPenjualanScreen({super.key, required this.storeId, required this.tanggal});

  @override
  State<RiwayatPenjualanScreen> createState() => _RiwayatPenjualanScreenState();
}

class _RiwayatPenjualanScreenState extends State<RiwayatPenjualanScreen> {
  late DateTime _bulan = DateTime(widget.tanggal.year, widget.tanggal.month, 1);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _filter = 'Semua';
  final Set<String> _buka = {};

  static const _filters = ['Semua', 'A Series', 'Reno Series', 'Find Series', 'IoT'];

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
      final akhir = DateTime(_bulan.year, _bulan.month + 1, 0);
      var q = Session.db
          .from('sales')
          .select('id,tanggal,tipe,grup,nama_produk,qty,subtotal,metode,cara_bayar,kategori_user,created_at,stores(nama)')
          .gte('tanggal', ymd(_bulan))
          .lte('tanggal', ymd(akhir));
      if (widget.storeId != null) q = q.eq('store_id', widget.storeId!);
      _rows = asList(await q.order('tanggal', ascending: false).order('created_at', ascending: false));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _geser(int n) {
    final b = DateTime(_bulan.year, _bulan.month + n, 1);
    if (b.isAfter(wibToday())) return;
    setState(() => _bulan = b);
    _load();
  }

  String _grupDari(Map<String, dynamic> r) => r['tipe'] == 'IOT' ? 'IoT' : '${r['grup'] ?? '-'}';

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => _filter == 'Semua' || _grupDari(r) == _filter).toList();
    final hp = list.where((r) => r['tipe'] == 'HP');
    final unitHp = hp.fold<num>(0, (a, r) => a + toNum(r['qty']));
    final unitIot = list.where((r) => r['tipe'] == 'IOT').fold<num>(0, (a, r) => a + toNum(r['qty']));
    final value = list.fold<num>(0, (a, r) => a + toNum(r['subtotal']));

    // grup -> tipe -> transaksi
    final grup = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final r in list) {
      grup.putIfAbsent(_grupDari(r), () => {}).putIfAbsent(namaTipe('${r['nama_produk']}'), () => []).add(r);
    }
    final grupUrut = grup.keys.toList()..sort((a, b) => urutanGrup(a).compareTo(urutanGrup(b)));
    final bisaMaju = !DateTime(_bulan.year, _bulan.month + 1, 1).isAfter(wibToday());

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat penjualan')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(children: [
            IconButton(onPressed: () => _geser(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(namaBulan(_bulan),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            IconButton(onPressed: bisaMaju ? () => _geser(1) : null, icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
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
                            child: Row(children: [
                              Expanded(child: _kpi('HP', '${angka(unitHp)} unit')),
                              Expanded(child: _kpi('IoT', '${angka(unitIot)} unit')),
                              Expanded(child: _kpi('Value', rupiah(value))),
                            ]),
                          ),
                        ),
                        if (list.isEmpty) const EmptyState(icon: Icons.receipt_long, text: 'Belum ada penjualan'),
                        for (final g in grupUrut) ..._grup(g, grup[g]!),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _kpi(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  List<Widget> _grup(String g, Map<String, List<Map<String, dynamic>>> tipe) {
    final c = warnaGrup(g);
    final unit = tipe.values.expand((l) => l).fold<num>(0, (a, r) => a + toNum(r['qty']));
    final tipeUrut = tipe.keys.toList()..sort();
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(g, style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 15))),
          Text('${angka(unit)} unit', style: TextStyle(fontWeight: FontWeight.bold, color: c)),
        ]),
      ),
      for (final t in tipeUrut) _tipeCard('$g|$t', t, tipe[t]!, c),
    ];
  }

  Widget _tipeCard(String key, String tipe, List<Map<String, dynamic>> trx, Color c) {
    final unit = trx.fold<num>(0, (a, r) => a + toNum(r['qty']));
    final value = trx.fold<num>(0, (a, r) => a + toNum(r['subtotal']));
    final buka = _buka.contains(key);
    // Ringkas per varian
    final varian = <String, num>{};
    for (final r in trx) {
      final v = namaVarian('${r['nama_produk']}');
      final k = v.isEmpty ? '${r['nama_produk']}' : v;
      varian[k] = (varian[k] ?? 0) + toNum(r['qty']);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(children: [
        ListTile(
          dense: true,
          onTap: () => setState(() => buka ? _buka.remove(key) : _buka.add(key)),
          title: Text(tipe, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text([for (final e in varian.entries) '${e.key}: ${angka(e.value)}'].join(' · ')),
          trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${angka(unit)} unit', style: TextStyle(fontWeight: FontWeight.bold, color: c)),
            Text(rupiah(value), style: const TextStyle(fontSize: 11)),
          ]),
        ),
        if (buka)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(children: [
              const Divider(height: 8),
              for (final r in trx)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 46,
                      child: Text(tglPendek(parseDate('${r['tanggal']}')), style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(
                        [
                          if (namaVarian('${r['nama_produk']}').isNotEmpty) namaVarian('${r['nama_produk']}'),
                          if (widget.storeId == null) '${asMap(r['stores'])['nama'] ?? ''}',
                          if (r['kategori_user'] != null) '${r['kategori_user']}',
                          if (r['cara_bayar'] != null) '${r['cara_bayar']}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text('x${r['qty']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}
