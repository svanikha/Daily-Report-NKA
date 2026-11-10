import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Gambar "Daily Report NKA" satu toko untuk dikirim ke grup WhatsApp.
class LaporanScreen extends StatefulWidget {
  final TokoHari toko;
  const LaporanScreen({super.key, required this.toko});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  final _key = GlobalKey();
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  Map<String, dynamic> _r = {};

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
      _r = asMap(await Session.db.rpc('rekap_toko', params: {'p_store': widget.toko.storeId, 'p_tanggal': widget.toko.tgl}));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw 'Gagal membuat gambar';
      final nama = widget.toko.toko.replaceAll(' ', '_');
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'DailyReportNKA_${nama}_${widget.toko.tgl}.png')],
        text: 'Daily Report NKA ${widget.toko.toko} · ${hariTgl(widget.toko.tanggal)}',
      ));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gambar laporan')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (_loading || _sharing || _error != null) ? null : _share,
            icon: busyIcon(_sharing, Icons.share),
            label: const Text('Kirim ke grup WhatsApp'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _key,
                        child: LaporanCard(tanggal: widget.toko.tanggal, r: _r),
                      ),
                    ),
                  ),
                ),
    );
  }
}

/// Isi gambar laporan (lebar tetap 360 agar hasilnya sama di semua HP).
class LaporanCard extends StatelessWidget {
  final DateTime tanggal;
  final Map<String, dynamic> r;
  const LaporanCard({super.key, required this.tanggal, required this.r});

  static const _ink = Color(0xFF1B2421);
  static const _muted = Color(0xFF66736E);
  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final hari = asMap(r['hari']);
    final bulan = asMap(r['bulan']);
    final target = asMap(r['target']);
    final laporan = r['laporan'] == null ? null : asMap(r['laporan']);
    final libur = r['libur'] as String?;
    final penjualan = asList(r['penjualan']);
    final kompetitor = asList(r['kompetitor']);
    final display = asList(r['display']);
    final stokKosong = (r['stok_kosong_fokus'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final stokWaktu = r['stok_waktu'] == null ? null : parseWib('${r['stok_waktu']}');

    // Sisa hari kerja setelah tanggal laporan s.d. akhir bulan (tanpa offday)
    final sisaHari = toNum(r['hari_akhir']).toInt() - tanggal.day - toNum(r['offday_sisa']).toInt();

    final unitHari = toNum(hari['unit']);
    final kompHari = toNum(hari['kompetitor']);
    final totalHari = unitHari + kompHari;
    final unitMs = toNum(bulan['unit_hari_kompetitor']);
    final kompBulan = toNum(bulan['kompetitor']);
    final cash = toNum(r['cash_unit']);
    final kredit = toNum(r['kredit_unit']);
    final bayar = cash + kredit;
    final displayOk = display.where((d) => d['ok'] == true).length;
    final ist = r['istirahat'] == null ? null : asMap(r['istirahat']);

    return Container(
      width: 360,
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: brandGreen,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DAILY REPORT NKA',
                style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${r['toko'] ?? ''}'.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(hariTgl(tanggal), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            Text('PC: ${r['pc'] ?? 'Non PC'} · TL: ${r['tl'] ?? '-'}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
        if (libur != null) _banner(libur == 'izin' ? 'PC IZIN HARI INI' : 'PC OFFDAY HARI INI', const Color(0xFF00897B)),
        // SELL-OUT
        _section('SELL-OUT OPPO', [
          Row(children: [
            Expanded(child: _stat('Unit HP hari ini', '${angka(unitHari)} unit', rupiah(toNum(hari['value'])))),
            const SizedBox(width: 8),
            Expanded(child: _stat('IoT hari ini', '${angka(toNum(hari['iot']))} unit', rupiah(toNum(hari['iot_value'])))),
          ]),
          const SizedBox(height: 6),
          if (penjualan.isEmpty)
            Text(r['nihil_penjualan'] == true ? 'NOSELL (dilaporkan tidak ada penjualan)' : 'Belum ada penjualan',
                style: const TextStyle(color: _red, fontWeight: FontWeight.w600, fontSize: 12))
          else
            for (final s in penjualan)
              _line('${s['nama']}', 'x${s['qty']}${s['cara_bayar'] != null ? ' · ${s['cara_bayar']}' : ''}', small: true),
        ]),
        // PENCAPAIAN BULAN INI
        _section('PENCAPAIAN ${namaBulan(tanggal).toUpperCase()}', [
          for (final d in targetDefs)
            _progress(
              d.label,
              toNum(bulan[d.jenis]),
              toNum(target[d.jenis]),
              d.rupiah ? rupiah : (v) => '${angka(v)} unit',
              sisaHari,
            ),
          Text(
            sisaHari > 0
                ? 'Target per hari = sisa target dibagi $sisaHari hari kerja tersisa'
                    '${toNum(r['offday_sisa']) > 0 ? ' (tanpa ${r['offday_sisa']} hari offday)' : ''}'
                : 'Tidak ada hari kerja tersisa bulan ini',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ]),
        // MARKET SHARE & KOMPETITOR
        _section('MARKET SHARE & KOMPETITOR', [
          if (r['kompetitor_terisi'] != true)
            const Text('Data kompetitor belum diisi', style: TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w600))
          else ...[
            _line('Market share hari ini',
                totalHari > 0 ? '${angka(unitHari)} dari ${angka(totalHari)} unit (${(unitHari / totalHari * 100).toStringAsFixed(0)}%)' : '-'),
            _line('Market share bulan ini',
                unitMs + kompBulan > 0 ? '${(unitMs / (unitMs + kompBulan) * 100).toStringAsFixed(0)}%' : '-'),
            const SizedBox(height: 4),
            Text(
              kompetitor.isEmpty
                  ? 'Kompetitor: tidak ada penjualan'
                  : 'Kompetitor: ${kompetitor.map((k) => '${k['brand']} ${k['unit']}').join(', ')}',
              style: const TextStyle(color: _ink, fontSize: 12),
            ),
          ],
        ]),
        // PEMBAYARAN
        if (bayar > 0)
          _section('PEMBAYARAN HP', [
            _line('Cash : Kredit',
                '${(cash / bayar * 100).toStringAsFixed(0)}% : ${(kredit / bayar * 100).toStringAsFixed(0)}%'),
            if (r['kredit_top'] != null) _line('Kredit terbanyak', '${r['kredit_top']}'),
          ]),
        // STOK & DISPLAY
        _section('STOK & DISPLAY', [
          _line(
            'Update stok',
            stokWaktu == null ? 'Belum diisi' : '${jamMenit(stokWaktu)} WIB${stokTerlambat(stokWaktu) ? ' (terlambat)' : ''}',
            color: stokWaktu == null || stokTerlambat(stokWaktu) ? _red : _green,
          ),
          if (stokWaktu != null)
            _line('Stok kosong tipe fokus', stokKosong.isEmpty ? 'Tidak ada' : stokKosong.join(', '),
                color: stokKosong.isEmpty ? _green : _red),
          _line(
            'Display',
            r['display_terisi'] != true
                ? 'Belum dicek'
                : (displayOk == display.length ? 'Lengkap' : 'Belum lengkap ($displayOk/${display.length})') +
                    (toNum(r['display_foto']) > 0 ? ' · ${r['display_foto']} foto' : ''),
            color: r['display_terisi'] == true && displayOk == display.length ? _green : _red,
          ),
          if (r['display_terisi'] == true && displayOk < display.length)
            Text('Kurang: ${display.where((d) => d['ok'] != true).map((d) => d['nama']).join(', ')}',
                style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
        if (ist != null)
          _section('ISTIRAHAT', [
            _line(
              'Pilihan ${toNum(ist['durasi_menit']) == 60 ? '1 jam' : '2 jam'}',
              ist['selesai'] == null
                  ? '${jamMenit(parseWib('${ist['mulai']}'))} - belum kembali'
                  : '${jamMenit(parseWib('${ist['mulai']}'))}-${jamMenit(parseWib('${ist['selesai']}'))}'
                      '${toNum(ist['terlambat_menit']) > 0 ? ' (telat ${ist['terlambat_menit']} mnt)' : ''}',
              color: ist['selesai'] == null || toNum(ist['terlambat_menit']) > 0 ? _red : _ink,
            ),
          ]),
        Container(
          color: const Color(0xFFF1F4F3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            laporan == null
                ? 'Laporan belum dikirim · dibuat ${tglJam(wibNow())} WIB'
                : 'Laporan dikirim ${tglJam(parseWib('${laporan['dikirim_pada']}'))} WIB',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
      ]),
    );
  }

  Widget _banner(String t, Color c) => Container(
        color: c.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
      );

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E9E7)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: brandGreen, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _stat(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFFF1F8F4), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
          Text(value, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(color: _ink, fontSize: 11)),
        ]),
      );

  Widget _line(String a, String b, {bool small = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(a, style: TextStyle(color: _ink, fontSize: small ? 11.5 : 12.5))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(b,
                textAlign: TextAlign.right,
                style: TextStyle(color: color ?? _ink, fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _progress(String label, num actual, num target, String Function(num) fmt, int sisaHari) {
    final p = target > 0 ? actual / target * 100 : 0.0;
    final c = target > 0 ? pctColor(p.toDouble()) : Colors.grey;
    final sisa = target - actual;
    final perHari = sisa > 0 && sisaHari > 0 ? sisa / sisaHari : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600))),
          Text(target > 0 ? '${p.toStringAsFixed(0)}%' : '-', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: target > 0 ? (p / 100).clamp(0.0, 1.0).toDouble() : 0,
            minHeight: 6,
            color: c,
            backgroundColor: const Color(0xFFE4E9E7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          target <= 0
              ? '${fmt(actual)} (target belum diatur)'
              : '${fmt(actual)} dari ${fmt(target)}'
                  '${sisa > 0 ? ' · sisa ${fmt(sisa)}${perHari > 0 ? ' · ${fmt(perHari.ceil())}/hari' : ''}' : ' · TERCAPAI'}',
          style: const TextStyle(color: _muted, fontSize: 10.5),
        ),
      ]),
    );
  }
}
