import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/kalender_penjualan.dart';
import '../../widgets/sell_out_card.dart';
import '../../widgets/widgets.dart';
import '../pc/istirahat_card.dart';
import 'activity_screen.dart';
import 'display_screen.dart';
import 'ms_allbrand_screen.dart';
import 'laporan_screen.dart';
import 'penjualan_screen.dart';
import 'stok_screen.dart';

/// Isi laporan satu toko pada satu tanggal: status tiap modul, istirahat,
/// pencapaian bulan ini, dan tombol kirim laporan. Dipakai beranda PC dan detail toko atasan.
class HariTokoView extends StatefulWidget {
  final TokoHari toko;

  /// Dipanggil setiap data selesai dimuat (beranda PC memakainya untuk menjadwalkan pengingat).
  final void Function(Map<String, dynamic> rekap)? onLoaded;
  const HariTokoView({super.key, required this.toko, this.onLoaded});

  @override
  State<HariTokoView> createState() => HariTokoViewState();
}

class HariTokoViewState extends State<HariTokoView> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Map<String, dynamic> _r = {};

  TokoHari get t => widget.toko.denganLibur(_r['libur'] as String? ?? widget.toko.libur);

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant HariTokoView old) {
    super.didUpdateWidget(old);
    if (old.toko.storeId != widget.toko.storeId || old.toko.tgl != widget.toko.tgl) load();
  }

  Future<void> load() async {
    setState(() {
      _loading = _r.isEmpty;
      _error = null;
    });
    try {
      _r = asMap(await Session.db.rpc('rekap_toko', params: {'p_store': widget.toko.storeId, 'p_tanggal': widget.toko.tgl}));
      try {
        // Activity sosmed & cek limit (tahap1f.sql). Jika belum dijalankan, bagian Activity dikosongkan.
        _r['activity'] = await Session.db.rpc('rekap_activity', params: {'p_store': widget.toko.storeId, 'p_tanggal': widget.toko.tgl});
      } catch (_) {}
      widget.onLoaded?.call(_r);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    load();
  }

  Future<void> _kirim() async {
    final ok = await confirmDialog(context, 'Kirim laporan?',
        'Laporan ${t.toko} ${tglPendek(t.tanggal)} akan ditandai terkirim. Data masih bisa dikoreksi sampai 22.30 WIB.',
        yes: 'Kirim');
    if (!ok) return;
    setState(() => _sending = true);
    try {
      await Session.db.rpc('kirim_laporan', params: {'p_store': t.storeId, 'p_tanggal': t.tgl});
      await load();
      if (mounted) _open(LaporanScreen(toko: t));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: load);
    final me = Session.current!;
    final hari = asMap(_r['hari']);
    final bulan = asMap(_r['bulan']);
    final target = asMap(_r['target']);
    final laporan = _r['laporan'] == null ? null : asMap(_r['laporan']);
    final kurang = (_r['kurang'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final stokWaktu = _r['stok_waktu'] == null ? null : parseWib('${_r['stok_waktu']}');
    final display = asList(_r['display']);
    final displayOk = display.where((d) => d['ok'] == true).length;
    final penjualan = asList(_r['penjualan']);
    final libur = _r['libur'] as String?;
    final hk = HariKerja.dari(t.tanggal, offdaySisa: toNum(_r['offday_sisa']).toInt());

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        if (libur != null)
          InfoBanner(
            'Hari ini ${libur == 'izin' ? 'IZIN' : 'OFFDAY'}: PC tidak wajib lapor.'
            '${me.isPc ? '' : ' TL/Trainer bisa melengkapi data toko jika perlu.'}',
            icon: Icons.beach_access,
            color: Colors.teal,
          ),
        _statusLaporan(laporan, kurang),
        TimegoneBar(hk: hk),
        SellOutCard(hari: hari, bulan: bulan, target: target, hk: hk),
        KalenderPenjualan(key: ValueKey('kal-${t.storeId}'), selected: t.tanggal, storeId: t.storeId),
        const SectionHeader('Laporan harian'),
        _tile(
          icon: Icons.inventory_2,
          title: 'Update stok',
          status: stokWaktu == null ? 'Belum diisi' : 'Diisi ${jamMenit(stokWaktu)}',
          ok: stokWaktu != null,
          onTap: () => _open(StokScreen(toko: t)),
        ),
        _tile(
          icon: Icons.point_of_sale,
          title: 'Penjualan OPPO',
          status: penjualan.isNotEmpty
              ? 'HP ${angka(toNum(hari['unit']))} unit · ${rupiah(toNum(hari['value']))} · IoT ${angka(toNum(hari['iot']))}'
              : (_r['nihil_penjualan'] == true ? 'Tidak ada penjualan (NOSELL)' : 'Belum ada penjualan'),
          ok: penjualan.isNotEmpty || _r['nihil_penjualan'] == true,
          onTap: () => _open(PenjualanScreen(toko: t)),
        ),
        _tile(
          icon: Icons.pie_chart,
          title: 'MS Allbrand',
          status: _r['kompetitor_terisi'] == true
              ? 'Brand lain ${angka(toNum(hari['kompetitor']))} unit · MS OPPO '
                  '${toNum(hari['unit']) + toNum(hari['kompetitor']) > 0 ? '${(toNum(hari['unit']) / (toNum(hari['unit']) + toNum(hari['kompetitor'])) * 100).toStringAsFixed(0)}%' : '-'}'
              : 'Belum diisi',
          ok: _r['kompetitor_terisi'] == true,
          onTap: () => _open(MsAllbrandScreen(toko: t)),
        ),
        _tile(
          icon: Icons.storefront,
          title: 'Cek display',
          status: _r['display_terisi'] == true
              ? '$displayOk/${display.length} checklist · ${_r['display_foto']} foto'
              : 'Belum diisi',
          ok: _r['display_terisi'] == true,
          warn: _r['display_terisi'] == true && displayOk < display.length,
          onTap: () => _open(DisplayScreen(toko: t)),
        ),
        _activityTile(),
        if (me.isPc && t.hariIni && libur == null) ...[
          const SectionHeader('Istirahat'),
          IstirahatCard(
            istirahat: _r['istirahat'] == null ? null : asMap(_r['istirahat']),
            toko: t.toko,
            onChanged: load,
          ),
        ] else if (_r['istirahat'] != null) ...[
          const SectionHeader('Istirahat'),
          _istirahatInfo(asMap(_r['istirahat'])),
        ],
        const SizedBox(height: 16),
        if (laporan == null && t.bolehIsiHarian)
          FilledButton.icon(
            onPressed: _sending ? null : _kirim,
            icon: busyIcon(_sending, Icons.send),
            label: const Text('Kirim laporan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _open(LaporanScreen(toko: t)),
          icon: const Icon(Icons.image),
          label: const Text('Lihat & bagikan gambar laporan'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }

  Widget _statusLaporan(Map<String, dynamic>? laporan, List<String> kurang) {
    if (laporan != null) {
      final pada = parseWib('${laporan['dikirim_pada']}');
      final tepat = isSameDay(pada, t.tanggal) && !lewatBatasLaporan(pada);
      return InfoBanner(
        'Laporan terkirim ${jamMenit(pada)} WIB${tepat ? '' : ' (terlambat)'}'
        '${laporan['catatan'] != null ? '\nCatatan: ${laporan['catatan']}' : ''}',
        icon: Icons.verified,
        color: tepat ? Colors.green.shade700 : Colors.orange.shade800,
      );
    }
    if (t.libur != null) return const SizedBox.shrink();
    final lewat = !t.hariIni || lewatBatasLaporan();
    if (lewat) {
      return InfoBanner('TIDAK LAPOR: laporan belum dikirim sampai 22.30 WIB.', icon: Icons.error, color: Colors.red.shade700);
    }
    final sisa = batasLaporanPada(t.tanggal).difference(wibNow());
    return InfoBanner(
      'Laporan belum dikirim · sisa ${sisa.inHours} jam ${sisa.inMinutes % 60} menit (batas 22.30 WIB)'
      '${kurang.isEmpty ? '\nSemua bagian sudah terisi, tekan Kirim laporan.' : '\nBelum: ${kurang.join(', ')}'}',
      icon: Icons.schedule,
      color: Colors.blueGrey,
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String status,
    required bool ok,
    bool warn = false,
    required VoidCallback onTap,
  }) {
    final c = !ok ? Colors.grey.shade600 : (warn ? Colors.orange.shade800 : Colors.green.shade700);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(status, style: TextStyle(color: c)),
        trailing: Icon(ok ? (warn ? Icons.warning_amber : Icons.check_circle) : Icons.radio_button_unchecked, color: c),
        onTap: onTap,
      ),
    );
  }

  /// Activity (sosmed & cek limit): tidak wajib untuk kirim laporan.
  Widget _activityTile() {
    final a = asMap(_r['activity']);
    final sosmed = asMap(a['sosmed_hari']).values.fold<num>(0, (x, v) => x + toNum(v));
    final leasing = asList(a['leasing_hari']);
    final approve = leasing.where((l) => l['hasil'] == 'Approve').length;
    final ada = sosmed > 0 || leasing.isNotEmpty;
    return _tile(
      icon: Icons.campaign,
      title: 'Activity (sosmed & cek limit)',
      status: ada ? 'Sosmed ${angka(sosmed)} · cek limit ${leasing.length} ($approve approve)' : 'Belum ada (opsional)',
      ok: ada,
      onTap: () => _open(ActivityScreen(toko: t)),
    );
  }

  Widget _istirahatInfo(Map<String, dynamic> b) {
    final mulai = parseWib('${b['mulai']}');
    final durasi = toNum(b['durasi_menit']).toInt();
    final label = labelDurasi(durasi);
    if (b['selesai'] == null) {
      final lewat = wibNow().difference(mulai).inMinutes - durasi;
      return Card(
        child: ListTile(
          leading: Icon(Icons.timer, color: lewat > 0 ? Colors.red.shade700 : Colors.amber.shade900),
          title: Text('Istirahat $label sejak ${jamMenit(mulai)}'),
          subtitle: Text(lewat > 0 ? 'Belum kembali · terlambat $lewat menit' : 'Masih istirahat'),
        ),
      );
    }
    final telat = toNum(b['terlambat_menit']).toInt();
    return Card(
      child: ListTile(
        leading: Icon(Icons.free_breakfast, color: telat > 0 ? Colors.red.shade700 : Colors.green.shade700),
        title: Text('Istirahat $label: ${jamMenit(mulai)} - ${jamMenit(parseWib('${b['selesai']}'))}'),
        subtitle: Text(telat > 0 ? 'Terlambat $telat menit' : 'Tepat waktu'),
      ),
    );
  }
}
