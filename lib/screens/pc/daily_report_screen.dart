import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/catalog.dart';
import '../../data/targets.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Gambar "Laporan Harian" PC untuk dikirim ke grup kerja WhatsApp.
class DailyReportScreen extends StatefulWidget {
  final Profile pc;
  const DailyReportScreen({super.key, required this.pc});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  final _key = GlobalKey();
  DateTime _tanggal = wibToday();
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  _Data? _d;

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
      final pc = widget.pc.id;
      final ds = ymd(_tanggal);
      final ms = ymd(monthStart(_tanggal));
      final res = await Future.wait<dynamic>([
        db.from('sales').select('tanggal,tipe,nama_produk,qty,subtotal').eq('pc_id', pc).gte('tanggal', ms).lte('tanggal', ds),
        loadTargets(pc, _tanggal),
        db.from('checkins').select('modul').eq('pc_id', pc).eq('tanggal', ds),
        db.rpc('rekap_pc', params: {'p_pc': pc, 'p_dari': ds, 'p_sampai': ds}),
        db.rpc('rekap_pc', params: {'p_pc': pc, 'p_dari': ms, 'p_sampai': ds}),
        db.from('leasing_checks').select('leasing,hasil,limit_disetujui').eq('pc_id', pc).eq('tanggal', ds).order('created_at'),
        db.from('checklist_items').select('id,nama').eq('aktif', true).order('urutan').order('id'),
        db.from('store_checklists').select('item_id').eq('pc_id', pc).eq('tanggal', ds),
        db.from('breaks').select('mulai,selesai,durasi_menit,flag').eq('pc_id', pc).eq('tanggal', ds),
        db.from('pc_day_status').select('status').eq('pc_id', pc).eq('tanggal', ds),
        // Offday setelah tanggal laporan s.d. akhir bulan: tidak dihitung sebagai hari kerja
        db
            .from('pc_day_status')
            .select('tanggal')
            .eq('pc_id', pc)
            .eq('status', 'offday')
            .gt('tanggal', ds)
            .lte('tanggal', ymd(monthEnd(_tanggal))),
      ]);
      final sales = asList(res[0]);
      final libur = asList(res[9]);
      _d = _Data(
        hari: sales.where((s) => s['tanggal'] == ds).toList(),
        bulan: sales,
        target: res[1] as Map<String, num>,
        nihilReport: asList(res[2]).any((c) => c['modul'] == 'report'),
        nihilActivity: asList(res[2]).any((c) => c['modul'] == 'activity'),
        rHari: asMap(res[3]),
        rBulan: asMap(res[4]),
        leasing: asList(res[5]),
        items: asList(res[6]),
        doneItems: asList(res[7]).map((r) => toNum(r['item_id']).toInt()).toSet(),
        istirahat: asList(res[8]).isEmpty ? null : asList(res[8]).first,
        libur: libur.isEmpty ? null : '${libur.first['status']}',
        offdaySisa: asList(res[10]).map((r) => '${r['tanggal']}').toSet().length,
      );
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      helpText: 'Tanggal laporan',
    );
    if (d != null) {
      _tanggal = dateOnly(d);
      _load();
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw 'Gagal membuat gambar';
      final nama = widget.pc.nama.split(' ').first;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'Laporan_${nama}_${ymd(_tanggal)}.png')],
        text: 'Laporan harian ${widget.pc.nama} · ${hariTgl(_tanggal)}',
      ));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan harian'),
        actions: [IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal')],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: (_loading || _sharing || _d == null) ? null : _share,
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
                        child: _ReportCard(pc: widget.pc, tanggal: _tanggal, d: _d!),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _Data {
  final List<Map<String, dynamic>> hari;
  final List<Map<String, dynamic>> bulan;
  final Map<String, num> target;
  final bool nihilReport;
  final bool nihilActivity;
  final Map<String, dynamic> rHari;
  final Map<String, dynamic> rBulan;
  final List<Map<String, dynamic>> leasing;
  final List<Map<String, dynamic>> items;
  final Set<int> doneItems;
  final Map<String, dynamic>? istirahat;
  final String? libur;
  final int offdaySisa;

  _Data({
    required this.hari,
    required this.bulan,
    required this.target,
    required this.nihilReport,
    required this.nihilActivity,
    required this.rHari,
    required this.rBulan,
    required this.leasing,
    required this.items,
    required this.doneItems,
    required this.istirahat,
    required this.libur,
    required this.offdaySisa,
  });
}

/// Isi gambar laporan (lebar tetap 360 agar hasilnya sama di semua HP).
class _ReportCard extends StatelessWidget {
  final Profile pc;
  final DateTime tanggal;
  final _Data d;
  const _ReportCard({required this.pc, required this.tanggal, required this.d});

  static const _ink = Color(0xFF1B2421);
  static const _muted = Color(0xFF66736E);

  num _sum(Iterable<Map<String, dynamic>> rows, String tipe, String f) =>
      rows.where((s) => s['tipe'] == tipe).fold<num>(0, (a, s) => a + toNum(s[f]));

  @override
  Widget build(BuildContext context) {
    final hpUnit = _sum(d.hari, 'HP', 'qty');
    final hpRp = _sum(d.hari, 'HP', 'subtotal');
    final iotUnit = _sum(d.hari, 'IOT', 'qty');
    final iotRp = _sum(d.hari, 'IOT', 'subtotal');
    final hpRpBulan = _sum(d.bulan, 'HP', 'subtotal');
    final iotUnitBulan = _sum(d.bulan, 'IOT', 'qty');
    final tHp = d.target['revenue_hp'] ?? 0;
    final tIot = d.target['iot_unit'] ?? 0;
    final tDb = d.target['database_baru'] ?? 0;
    // Detail revenue HP: unit terjual bulan ini, sisa target, dan target per hari mulai besok
    final hpUnitBulan = _sum(d.bulan, 'HP', 'qty');
    final sisaHp = tHp - hpRpBulan > 0 ? tHp - hpRpBulan : 0;
    // Hari kerja setelah tanggal laporan s.d. akhir bulan (offday tidak dihitung)
    final sisaHariBesok = monthEnd(tanggal).day - tanggal.day - d.offdaySisa;
    final targetBesok = sisaHariBesok > 0 ? sisaHp / sisaHariBesok : 0;
    final sos = asMap(d.rHari['sosmed']);
    final ist = d.istirahat;
    final now = wibNow();

    return Container(
      width: 360,
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: brandGreen,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('LAPORAN HARIAN', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(pc.nama, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(pc.toko, style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 6),
            Text(hariTgl(tanggal), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (d.libur != null)
          _banner(d.libur == 'izin' ? 'Hari ini IZIN' : 'Hari ini OFFDAY', const Color(0xFF00897B)),
        // PENJUALAN
        _section('PENJUALAN', [
          Row(children: [
            Expanded(child: _stat('HP', '${angka(hpUnit)} unit', rupiah(hpRp))),
            const SizedBox(width: 8),
            Expanded(child: _stat('IoT', '${angka(iotUnit)} unit', rupiah(iotRp))),
          ]),
          const SizedBox(height: 6),
          if (d.hari.isEmpty)
            Text(d.nihilReport ? 'NOSELL (dilaporkan nihil)' : 'Belum ada penjualan',
                style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600, fontSize: 12))
          else
            for (final s in d.hari)
              _line('${s['nama_produk']}', 'x${s['qty']}', small: true),
        ]),
        // PENCAPAIAN BULAN INI
        _section('PENCAPAIAN ${namaBulan(tanggal).toUpperCase()}', [
          _progress('Revenue HP', rupiah(hpRpBulan), hpRpBulan, tHp, rupiah(tHp)),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(color: const Color(0xFFF1F8F4), borderRadius: BorderRadius.circular(6)),
            child: Column(children: [
              _line('Total unit HP terjual', '${angka(hpUnitBulan)} unit', small: true),
              if (tHp > 0) ...[
                _line('Sisa target revenue', sisaHp > 0 ? rupiah(sisaHp) : 'Target tercapai',
                    small: true, color: sisaHp > 0 ? const Color(0xFFC62828) : const Color(0xFF2E7D32)),
                _line(
                  'Target revenue besok',
                  sisaHp <= 0
                      ? '-'
                      : (sisaHariBesok > 0
                          ? '${rupiah(targetBesok.round())}/hari'
                          : (d.offdaySisa > 0 ? 'Tidak ada hari kerja' : 'Akhir bulan')),
                  small: true,
                ),
                if (sisaHp > 0 && sisaHariBesok > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                        d.offdaySisa > 0
                            ? 'sisa target dibagi $sisaHariBesok hari kerja tersisa (tanpa ${d.offdaySisa} hari offday)'
                            : 'sisa target dibagi $sisaHariBesok hari kerja tersisa bulan ini',
                        style: const TextStyle(color: _muted, fontSize: 10)),
                  ),
              ],
            ]),
          ),
          _progress('IoT', '${angka(iotUnitBulan)} unit', iotUnitBulan, tIot, '${angka(tIot)} unit'),
          _progress('Database baru', angka(toNum(d.rBulan['db_baru'])), toNum(d.rBulan['db_baru']), tDb, angka(tDb)),
        ]),
        // DATABASE
        _section('DATABASE', [
          _line('Database baru hari ini', angka(toNum(d.rHari['db_baru']))),
          _line('User dihubungi hari ini', angka(toNum(d.rHari['dihubungi_unik']))),
        ]),
        // ACTIVITY
        _section('ACTIVITY', [
          for (final s in sosmedDefs)
            if (toNum(sos[s.kode]) > 0) _line(s.label, '${angka(toNum(sos[s.kode]))} ${s.satuan}'),
          if (sos.values.every((v) => toNum(v) == 0))
            Text(d.nihilActivity ? 'Sosmed: nihil' : 'Sosmed: belum ada',
                style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          if (d.leasing.isEmpty)
            const Text('Cek limit leasing: belum ada', style: TextStyle(color: _muted, fontSize: 12))
          else
            for (final l in d.leasing)
              _line('Leasing ${l['leasing']}',
                  l['hasil'] == 'Approve' ? 'Approve ${rupiah(toNum(l['limit_disetujui']))}' : 'Reject',
                  color: l['hasil'] == 'Approve' ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
        ]),
        // CHECKLIST
        _section('CHECKLIST TOKO (${d.items.where((i) => d.doneItems.contains(toNum(i['id']).toInt())).length}/${d.items.length})', [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in d.items)
              _chip('${i['nama']}', d.doneItems.contains(toNum(i['id']).toInt())),
          ]),
        ]),
        // ISTIRAHAT
        if (ist != null)
          _section('ISTIRAHAT', [
            _line(
              'Pilihan ${toNum(ist['durasi_menit'] ?? 180) == 60 ? '1 jam' : '3 jam'}',
              _istirahatText(ist),
            ),
          ]),
        Container(
          color: const Color(0xFFF1F4F3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Daily Report NKA · dibuat ${tglJam(now)} WIB',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
      ]),
    );
  }

  String _istirahatText(Map<String, dynamic> b) {
    String jam(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    final mulai = parseWib(b['mulai'] as String);
    if (b['selesai'] == null) return '${jam(mulai)} - belum kembali';
    final selesai = parseWib(b['selesai'] as String);
    return '${jam(mulai)}-${jam(selesai)} (${selesai.difference(mulai).inMinutes} menit)';
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
          Text(b, style: TextStyle(color: color ?? _ink, fontSize: small ? 11.5 : 12.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _progress(String label, String actualText, num actual, num target, String targetText) {
    final p = target > 0 ? actual / target * 100 : 0.0;
    final c = target > 0 ? pctColor(p.toDouble()) : Colors.grey;
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
        Text(target > 0 ? '$actualText dari $targetText' : '$actualText (target belum diatur)',
            style: const TextStyle(color: _muted, fontSize: 10.5)),
      ]),
    );
  }

  Widget _chip(String t, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ok ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 13, color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(color: _ink, fontSize: 11)),
        ]),
      );
}
