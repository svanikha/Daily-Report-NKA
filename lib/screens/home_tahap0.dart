import 'package:flutter/material.dart';

import '../services/session.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'pc/account_screen.dart' show changePasswordDialog, logout;

/// Beranda sementara (Tahap 0): memastikan login, peran, toko/area, dan titik GPS
/// sudah terhubung dengan benar. Fitur laporan dibuat di Tahap 1.
class HomeTahap0 extends StatefulWidget {
  final Profile profile;
  const HomeTahap0({super.key, required this.profile});

  @override
  State<HomeTahap0> createState() => _HomeTahap0State();
}

class _HomeTahap0State extends State<HomeTahap0> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report NKA'),
        actions: [
          IconButton(
            tooltip: 'Ganti password',
            icon: const Icon(Icons.key),
            onPressed: () => changePasswordDialog(context),
          ),
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const InfoBanner(
          'Akun sudah terhubung. Menu laporan harian (stok, penjualan, kompetitor, display, istirahat) '
          'akan tersedia di update berikutnya.',
          icon: Icons.construction,
          color: brandGreen,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nama, style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Pill(p.roleLabel, color: brandGreen),
              const SizedBox(height: 12),
              if (p.isPc) _row(Icons.store, 'Toko', p.toko),
              if (!p.isPic) _row(Icons.map, 'Area', p.area.isEmpty ? '-' : p.area),
              if (p.isPic) _row(Icons.public, 'Cakupan', 'Semua area'),
            ]),
          ),
        ),
        if (p.isPc) ...[
          const SectionHeader('Titik lokasi toko'),
          if (p.lokasi.isEmpty)
            const ListTile(title: Text('Belum ada titik GPS. Hubungi Trainer atau PIC NKA.'))
          else
            for (final l in p.lokasi)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: brandGreen),
                  title: Text(l.nama),
                  subtitle: Text('${l.lat.toStringAsFixed(6)}, ${l.lng.toStringAsFixed(6)} · radius ${l.radiusM} m'),
                ),
              ),
        ],
        const SizedBox(height: 24),
        Center(child: Text('Daily Report NKA · versi ${UpdateService.versionName}', style: t.bodySmall)),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text(label)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
