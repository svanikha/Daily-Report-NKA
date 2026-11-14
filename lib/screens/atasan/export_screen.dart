import 'dart:typed_data';

import 'package:excel/excel.dart'
    show CellIndex, CellStyle, CellValue, DoubleCellValue, Excel, IntCellValue, TextCellValue;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../riwayat_screens.dart';

/// Tarik data activity PC ke Excel (TL / Trainer / PIC): pilih rentang tanggal & toko.
/// Sheet: Ringkasan harian (sell out HP, value, tipe fokus, IoT, stok, MS Allbrand, cek limit, Avanto),
/// Total per toko, Penjualan, Stok, MS Allbrand, Cek limit.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late DateTimeRange _rentang = DateTimeRange(
    start: DateTime(wibToday().year, wibToday().month, 1),
    end: wibToday(),
  );
  int? _store;
  List<Map<String, dynamic>> _toko = [];
  bool _busy = false;
  String? _hasil;

  @override
  void initState() {
    super.initState();
    tokoCakupan().then((t) {
      if (mounted) setState(() => _toko = t);
    }).catchError((_) {});
  }

  Future<void> _pilihTanggal() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      initialDateRange: _rentang,
      helpText: 'Rentang tanggal data',
    );
    if (r != null) setState(() => _rentang = DateTimeRange(start: dateOnly(r.start), end: dateOnly(r.end)));
  }

  void _cepat(String p) {
    final t = wibToday();
    setState(() {
      switch (p) {
        case 'hari':
          _rentang = DateTimeRange(start: t, end: t);
        case '7':
          _rentang = DateTimeRange(start: addDays(t, -6), end: t);
        case 'bulan':
          _rentang = DateTimeRange(start: DateTime(t.year, t.month, 1), end: t);
        case 'lalu':
          _rentang = DateTimeRange(start: DateTime(t.year, t.month - 1, 1), end: DateTime(t.year, t.month, 0));
      }
    });
  }

  Future<void> _export() async {
    if (_rentang.end.difference(_rentang.start).inDays > 92) {
      showMsg(context, 'Rentang maksimal 3 bulan (93 hari)');
      return;
    }
    setState(() {
      _busy = true;
      _hasil = null;
    });
    try {
      final d = asMap(await Session.db.rpc('export_data', params: {
        'p_dari': ymd(_rentang.start),
        'p_sampai': ymd(_rentang.end),
        'p_store': _store,
      }));
      final bytes = _buatExcel(d);
      final namaToko = _store == null
          ? 'Semua'
          : '${_toko.firstWhere((t) => toNum(t['id']).toInt() == _store, orElse: () => {'nama': 'Toko'})['nama']}'
              .replaceAll(' ', '_');
      final nama = 'DailyReportNKA_${namaToko}_${ymd(_rentang.start)}_sd_${ymd(_rentang.end)}.xlsx';
      setState(() => _hasil = '${asList(d['harian']).length} baris harian · ${asList(d['penjualan']).length} penjualan · '
          '${asList(d['cek_limit']).length} cek limit');
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(bytes,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: nama),
        ],
        fileNameOverrides: [nama],
        text: 'Data Daily Report NKA ${tglPendek(_rentang.start)} - ${tglPendek(_rentang.end)}',
      ));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  // ------------------------------------------------------------------
  Uint8List _buatExcel(Map<String, dynamic> d) {
    final x = Excel.createExcel();
    final bawaan = x.getDefaultSheet() ?? 'Sheet1';

    final harian = asList(d['harian']);
    _sheet(x, 'Ringkasan harian', const [
      'Tanggal', 'Area', 'Toko', 'PC', 'Status PC', 'Laporan', 'Unit HP', 'Value HP', 'Fokus A7 Pro', 'Fokus Reno 16',
      'Unit IoT', 'Value IoT', 'Stok HP', 'Stok IoT', 'MS brand lain', 'MS OPPO %', 'Cek limit', 'Cek Avanto',
      'Avanto approve', 'Sosmed',
    ], [
      for (final r in harian)
        [
          r['tanggal'], r['area'], r['toko'], r['pc'], r['libur'] ?? 'masuk', r['laporan'] ?? '-', r['unit_hp'],
          r['value_hp'], r['fokus_a7pro'], r['fokus_reno16'], r['unit_iot'], r['value_iot'], r['stok_hp'],
          r['stok_iot'], r['ms_brand_lain'], r['ms_oppo_pct'], r['cek_limit'], r['cek_avanto'], r['avanto_approve'],
          r['sosmed'],
        ],
    ]);

    // Total per toko selama rentang
    final perToko = <String, Map<String, num>>{};
    final areaToko = <String, String>{};
    const kolom = [
      'unit_hp', 'value_hp', 'fokus_a7pro', 'fokus_reno16', 'unit_iot', 'value_iot', 'ms_brand_lain', 'cek_limit',
      'cek_avanto', 'avanto_approve', 'sosmed',
    ];
    for (final r in harian) {
      final k = '${r['toko']}';
      areaToko[k] = '${r['area']}';
      final m = perToko.putIfAbsent(k, () => {for (final c in kolom) c: 0});
      for (final c in kolom) {
        m[c] = m[c]! + toNum(r[c]);
      }
      if (r['laporan'] != null) m['lapor'] = (m['lapor'] ?? 0) + 1;
    }
    _sheet(x, 'Total per toko', const [
      'Area', 'Toko', 'Unit HP', 'Value HP', 'Fokus A7 Pro', 'Fokus Reno 16', 'Unit IoT', 'Value IoT', 'MS brand lain',
      'MS OPPO %', 'Cek limit', 'Cek Avanto', 'Avanto approve', 'Sosmed', 'Hari lapor',
    ], [
      for (final e in perToko.entries)
        [
          areaToko[e.key], e.key, e.value['unit_hp'], e.value['value_hp'], e.value['fokus_a7pro'],
          e.value['fokus_reno16'], e.value['unit_iot'], e.value['value_iot'], e.value['ms_brand_lain'],
          e.value['unit_hp']! + e.value['ms_brand_lain']! > 0
              ? (e.value['unit_hp']! * 100 / (e.value['unit_hp']! + e.value['ms_brand_lain']!)).round()
              : null,
          e.value['cek_limit'], e.value['cek_avanto'], e.value['avanto_approve'], e.value['sosmed'],
          e.value['lapor'] ?? 0,
        ],
    ]);

    _sheet(x, 'Penjualan', const [
      'Tanggal', 'Toko', 'Tipe', 'Series', 'Produk', 'Qty', 'Harga', 'Subtotal', 'Kategori user', 'Metode', 'Cara bayar',
    ], [
      for (final r in asList(d['penjualan']))
        [
          r['tanggal'], r['toko'], r['tipe'], r['grup'], r['produk'], r['qty'], r['harga'], r['subtotal'],
          r['kategori_user'], r['metode'], r['cara_bayar'],
        ],
    ]);

    _sheet(x, 'Stok', const ['Tanggal', 'Toko', 'Tipe', 'Series', 'Produk', 'Qty'], [
      for (final r in asList(d['stok'])) [r['tanggal'], r['toko'], r['tipe'], r['grup'], r['produk'], r['qty']],
    ]);

    const seg = {'lt3': '< 3 jt', '3to6': '3 - 6 jt', 'gt6': '6 jt up'};
    _sheet(x, 'MS Allbrand', const ['Tanggal', 'Toko', 'Brand', 'Segmen', 'Unit'], [
      for (final r in asList(d['ms_allbrand'])) [r['tanggal'], r['toko'], r['brand'], seg[r['segmen']] ?? r['segmen'], r['unit']],
    ]);

    _sheet(x, 'Cek limit', const ['Tanggal', 'Jam', 'Toko', 'Leasing', 'Hasil', 'Limit disetujui'], [
      for (final r in asList(d['cek_limit'])) [r['tanggal'], r['jam'], r['toko'], r['leasing'], r['hasil'], r['limit']],
    ]);

    x.setDefaultSheet('Ringkasan harian');
    if (bawaan != 'Ringkasan harian') x.delete(bawaan);
    final out = x.encode();
    if (out == null) throw 'Gagal membuat file Excel';
    return Uint8List.fromList(out);
  }

  void _sheet(Excel x, String nama, List<String> header, List<List<dynamic>> rows) {
    final s = x[nama];
    s.appendRow([for (final h in header) TextCellValue(h)]);
    for (var c = 0; c < header.length; c++) {
      s.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(header[c]),
        cellStyle: CellStyle(bold: true),
      );
      s.setColumnWidth(c, c < 5 ? 16 : 13);
    }
    for (final r in rows) {
      s.appendRow([for (final v in r) _cell(v)]);
    }
  }

  CellValue? _cell(dynamic v) {
    if (v == null) return null;
    if (v is int) return IntCellValue(v);
    if (v is double) return v == v.roundToDouble() ? IntCellValue(v.toInt()) : DoubleCellValue(v);
    if (v is num) return DoubleCellValue(v.toDouble());
    return TextCellValue('$v');
  }

  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final hari = _rentang.end.difference(_rentang.start).inDays + 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Export data Excel')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: busyIcon(_busy, Icons.file_download),
            label: const Text('Buat & bagikan Excel'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const InfoBanner(
          'Isi file: ringkasan harian per toko (sell out HP, value, tipe fokus A7 Pro & Reno 16, IoT, stok, '
          'MS Allbrand, cek limit, Avanto), total per toko, daftar penjualan, stok per produk, MS Allbrand per brand, '
          'dan cek limit.',
          icon: Icons.table_chart,
        ),
        const SectionHeader('Rentang tanggal'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.date_range),
            title: Text('${hariTgl(_rentang.start)} - ${hariTgl(_rentang.end)}'),
            subtitle: Text('$hari hari · maksimal 93 hari'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _pilihTanggal,
          ),
        ),
        Wrap(spacing: 6, children: [
          ActionChip(label: const Text('Hari ini'), onPressed: () => _cepat('hari')),
          ActionChip(label: const Text('7 hari'), onPressed: () => _cepat('7')),
          ActionChip(label: const Text('Bulan ini'), onPressed: () => _cepat('bulan')),
          ActionChip(label: const Text('Bulan lalu'), onPressed: () => _cepat('lalu')),
        ]),
        const SectionHeader('Toko'),
        DropdownButtonFormField<int?>(
          initialValue: _store,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.store), isDense: true),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Semua toko di cakupan akun')),
            for (final t in _toko) DropdownMenuItem<int?>(value: toNum(t['id']).toInt(), child: Text('${t['nama']}')),
          ],
          onChanged: (v) => setState(() => _store = v),
        ),
        if (_hasil != null) ...[
          const SizedBox(height: 16),
          InfoBanner('File dibuat: $_hasil', icon: Icons.check_circle, color: Colors.green.shade700),
        ],
      ]),
    );
  }
}
