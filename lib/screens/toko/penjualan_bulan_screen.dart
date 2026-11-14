import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import 'penjualan_screen.dart';
import 'sale_form.dart';

/// Riwayat penjualan satu toko selama satu bulan, dikelompokkan per tanggal.
/// Ketuk penjualan untuk mengubah (PC: tgl 1 s.d. hari ini di bulan berjalan), ikon tempat sampah
/// untuk menghapus, dan ketuk judul tanggal untuk membuka / menambah penjualan tanggal itu.
class PenjualanBulanScreen extends StatefulWidget {
  final TokoHari toko;

  /// 'HP', 'IOT', atau null (semua)
  final String? tipe;
  const PenjualanBulanScreen({super.key, required this.toko, this.tipe});

  @override
  State<PenjualanBulanScreen> createState() => _PenjualanBulanScreenState();
}

class _PenjualanBulanScreenState extends State<PenjualanBulanScreen> {
  late DateTime _bulan = DateTime(widget.toko.tanggal.year, widget.toko.tanggal.month, 1);
  late String? _tipe = widget.tipe;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _changed = false;

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final akhir = DateTime(_bulan.year, _bulan.month + 1, 0);
      _rows = asList(await Session.db
          .from('sales')
          .select('id,tipe,product_id,grup,nama_produk,qty,harga,subtotal,metode,cara_bayar,kategori_user,tanggal,created_at')
          .eq('store_id', t.storeId)
          .gte('tanggal', ymd(_bulan))
          .lte('tanggal', ymd(akhir))
          .order('tanggal', ascending: false)
          .order('created_at', ascending: false));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _geser(int n) {
    final b = DateTime(_bulan.year, _bulan.month + n, 1);
    if (b.isAfter(wibToday())) return;
    setState(() {
      _bulan = b;
      _rows = [];
    });
    _load();
  }

  bool _boleh(DateTime tgl) => t.padaTanggal(tgl).bolehIsiPenjualan;

  Future<void> _ubah(Map<String, dynamic> r) async {
    final tgl = parseDate('${r['tanggal']}');
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SaleForm(toko: t.padaTanggal(tgl), tipe: '${r['tipe']}', sale: r),
    ));
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _hapus(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Hapus penjualan?',
        '${r['nama_produk']} x${r['qty']} · ${hariTgl(parseDate('${r['tanggal']}'))}', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('sales').delete().eq('id', '${r['id']}');
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _bukaTanggal(DateTime d) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PenjualanScreen(toko: t.padaTanggal(d))));
    if (ok == true) _changed = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => _tipe == null || r['tipe'] == _tipe).toList();
    final unitHp = list.where((r) => r['tipe'] == 'HP').fold<num>(0, (a, r) => a + toNum(r['qty']));
    final unitIot = list.where((r) => r['tipe'] == 'IOT').fold<num>(0, (a, r) => a + toNum(r['qty']));
    final value = list.fold<num>(0, (a, r) => a + toNum(r['subtotal']));
    final perTgl = <String, List<Map<String, dynamic>>>{};
    for (final r in list) {
      perTgl.putIfAbsent('${r['tanggal']}', () => []).add(r);
    }
    final bisaMaju = !DateTime(_bulan.year, _bulan.month + 1, 1).isAfter(wibToday());
    final me = Session.current;
    final bulanIni = _bulan.year == wibToday().year && _bulan.month == wibToday().month;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Riwayat penjualan'),
            Text(t.toko, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ]),
        ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Semua', label: Text('Semua')),
                ButtonSegment(value: 'HP', label: Text('HP'), icon: Icon(Icons.smartphone)),
                ButtonSegment(value: 'IOT', label: Text('IoT'), icon: Icon(Icons.watch)),
              ],
              selected: {_tipe ?? 'Semua'},
              onSelectionChanged: (s) => setState(() => _tipe = s.first == 'Semua' ? null : s.first),
            ),
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
                          if (me?.isPc ?? false)
                            InfoBanner(
                              bulanIni
                                  ? 'Ketuk penjualan untuk mengubah jika salah input. Bisa untuk tgl 1 s.d. hari ini di bulan ini.'
                                  : 'Bulan lalu hanya bisa dilihat. Hubungi TL jika ada koreksi.',
                              icon: Icons.edit_note,
                            ),
                          if (list.isEmpty) const EmptyState(icon: Icons.receipt_long, text: 'Belum ada penjualan'),
                          for (final e in perTgl.entries) ..._tanggal(e.key, e.value),
                        ]),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _kpi(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  List<Widget> _tanggal(String tgl, List<Map<String, dynamic>> rows) {
    final d = parseDate(tgl);
    final hp = rows.where((r) => r['tipe'] == 'HP').fold<num>(0, (a, r) => a + toNum(r['qty']));
    final iot = rows.where((r) => r['tipe'] == 'IOT').fold<num>(0, (a, r) => a + toNum(r['qty']));
    final value = rows.fold<num>(0, (a, r) => a + toNum(r['subtotal']));
    final boleh = _boleh(d);
    return [
      InkWell(
        onTap: () => _bukaTanggal(d),
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(children: [
            Expanded(child: Text(hariTgl(d), style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('HP ${angka(hp)} · IoT ${angka(iot)} · ${rupiah(value)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ]),
        ),
      ),
      for (final r in rows)
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            onTap: boleh ? () => _ubah(r) : null,
            leading: Icon(r['tipe'] == 'HP' ? Icons.smartphone : Icons.watch),
            title: Text('${r['nama_produk']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              'x${r['qty']} · ${rupiah(toNum(r['subtotal']))}',
              if (r['kategori_user'] != null) '${r['kategori_user']}',
              if (r['metode'] != null) '${r['metode']} ${r['cara_bayar'] ?? ''}',
            ].join(' · ')),
            trailing: boleh
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Ubah', icon: const Icon(Icons.edit_outlined), onPressed: () => _ubah(r)),
                    IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete_outline), onPressed: () => _hapus(r)),
                  ])
                : null,
          ),
        ),
    ];
  }
}
