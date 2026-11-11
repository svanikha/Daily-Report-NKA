import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../utils.dart';
import '../../widgets/pengingat_pc.dart';
import '../toko/hari_toko_view.dart';

/// Detail satu toko untuk TL / Trainer / PIC: sama dengan beranda PC, tanggal bisa dipilih.
class TokoDetailScreen extends StatefulWidget {
  final TokoHari toko;
  const TokoDetailScreen({super.key, required this.toko});

  @override
  State<TokoDetailScreen> createState() => _TokoDetailScreenState();
}

class _TokoDetailScreenState extends State<TokoDetailScreen> {
  final _view = GlobalKey<HariTokoViewState>();
  late TokoHari _toko = widget.toko;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toko.tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      helpText: 'Tanggal laporan',
    );
    if (d == null) return;
    setState(() => _toko = TokoHari(
          storeId: _toko.storeId,
          toko: _toko.toko,
          area: _toko.area,
          pcId: _toko.pcId,
          pcNama: _toko.pcNama,
          punyaPc: _toko.punyaPc,
          tanggal: dateOnly(d),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_toko.toko),
          Text('${_toko.punyaPc ? 'PC: ${_toko.pcNama ?? '-'}' : 'Non PC'} · ${tglPendek(_toko.tanggal)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          if (_toko.punyaPc && _toko.pcId != null)
            IconButton(
              onPressed: () => showKirimPengingat(context, storeId: _toko.storeId, toko: _toko.toko, pcNama: _toko.pcNama),
              icon: const Icon(Icons.notifications_active),
              tooltip: 'Ingatkan PC',
            ),
          IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal'),
          IconButton(onPressed: () => _view.currentState?.load(), icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ],
      ),
      body: HariTokoView(key: _view, toko: _toko),
    );
  }
}
