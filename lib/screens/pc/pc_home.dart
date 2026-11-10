import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/akun.dart';
import '../../services/notif_service.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../toko/hari_toko_view.dart';

/// Beranda PC: laporan hari ini untuk tokonya sendiri.
class PcHome extends StatefulWidget {
  final Profile pc;
  const PcHome({super.key, required this.pc});

  @override
  State<PcHome> createState() => _PcHomeState();
}

class _PcHomeState extends State<PcHome> {
  final _view = GlobalKey<HariTokoViewState>();
  late final TokoHari _toko = TokoHari.dariPc(widget.pc);

  @override
  void initState() {
    super.initState();
    NotifService.requestPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  /// Jadwalkan ulang pengingat stok, laporan, dan istirahat setiap data dimuat.
  Future<void> _jadwalkan(Map<String, dynamic> r) async {
    try {
      final today = wibToday();
      final rows = asList(await Session.db
          .from('pc_day_status')
          .select('tanggal')
          .eq('pc_id', widget.pc.id)
          .gte('tanggal', ymd(today))
          .lte('tanggal', ymd(addDays(today, 7))));
      final b = r['istirahat'] == null ? null : asMap(r['istirahat']);
      await NotifService.reschedule(
        offdays: {for (final x in rows) '${x['tanggal']}'},
        stokDone: r['stok_waktu'] != null,
        laporanDone: r['laporan'] != null,
        breakStart: b != null && b['selesai'] == null ? parseWib('${b['mulai']}') : null,
        breakMenit: b == null ? 60 : toNum(b['durasi_menit']).toInt(),
      );
    } catch (_) {
      // Tanpa internet: pengingat dijadwalkan lagi saat aplikasi dibuka berikutnya.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.pc.toko),
          Text('${widget.pc.nama} · ${hariTgl(_toko.tanggal)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          IconButton(onPressed: () => _view.currentState?.load(), icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
          const AkunMenuButton(),
        ],
      ),
      body: HariTokoView(key: _view, toko: _toko, onLoaded: _jadwalkan),
    );
  }
}
