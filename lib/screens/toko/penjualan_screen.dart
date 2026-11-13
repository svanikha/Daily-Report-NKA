import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/kontribusi_tipe.dart';
import '../../widgets/widgets.dart';
import 'sale_form.dart';

/// Daftar penjualan OPPO satu toko pada satu tanggal + tombol tambah HP / IoT.
class PenjualanScreen extends StatefulWidget {
  final TokoHari toko;
  const PenjualanScreen({super.key, required this.toko});

  @override
  State<PenjualanScreen> createState() => _PenjualanScreenState();
}

class _PenjualanScreenState extends State<PenjualanScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  bool _nihil = false;
  bool _changed = false;

  TokoHari get t => widget.toko;

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
      final res = await Future.wait<dynamic>([
        db
            .from('sales')
            .select('id,tipe,nama_produk,qty,harga,subtotal,metode,cara_bayar,kategori_user,tanggal,created_at')
            .eq('store_id', t.storeId)
            .eq('tanggal', t.tgl)
            .order('created_at'),
        db.from('checkins').select('modul').eq('store_id', t.storeId).eq('tanggal', t.tgl).eq('modul', 'penjualan'),
      ]);
      _rows = asList(res[0]);
      _nihil = asList(res[1]).isNotEmpty;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add(String tipe) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SaleForm(toko: t, tipe: tipe)));
    if (ok == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Hapus penjualan?', '${r['nama_produk']} x${r['qty']}', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('sales').delete().eq('id', r['id'] as String);
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _setNihil(bool v) async {
    try {
      if (v) {
        await Session.db.from('checkins').upsert(
          {'store_id': t.storeId, 'tanggal': t.tgl, 'modul': 'penjualan', 'oleh': Session.current?.id},
          onConflict: 'store_id,tanggal,modul',
        );
      } else {
        await Session.db.from('checkins').delete().eq('store_id', t.storeId).eq('tanggal', t.tgl).eq('modul', 'penjualan');
      }
      _changed = true;
      setState(() => _nihil = v);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  num _sum(String tipe, String f) => _rows.where((r) => r['tipe'] == tipe).fold<num>(0, (a, r) => a + toNum(r[f]));

  @override
  Widget build(BuildContext context) {
    final bolehJual = t.bolehIsiPenjualan;
    final bolehNihil = t.bolehIsiHarian;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Penjualan OPPO'),
            Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Riwayat per series & tipe',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RiwayatPenjualanScreen(storeId: t.storeId, tanggal: t.tanggal),
              )),
            ),
          ],
        ),
        bottomNavigationBar: !bolehJual
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _add('HP'),
                        icon: const Icon(Icons.smartphone),
                        label: const Text('+ HP'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _add('IOT'),
                        icon: const Icon(Icons.watch),
                        label: const Text('+ IoT'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ]),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorRetry(error: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.all(12), children: [
                      StatGrid(children: [
                        StatCard(
                          label: 'HP',
                          value: '${angka(_sum('HP', 'qty'))} unit',
                          sub: rupiah(_sum('HP', 'subtotal')),
                          icon: Icons.smartphone,
                        ),
                        StatCard(
                          label: 'IoT',
                          value: '${angka(_sum('IOT', 'qty'))} unit',
                          sub: rupiah(_sum('IOT', 'subtotal')),
                          icon: Icons.watch,
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (_rows.isEmpty)
                        Card(
                          child: SwitchListTile(
                            value: _nihil,
                            onChanged: bolehNihil ? _setNihil : null,
                            title: const Text('Tidak ada penjualan hari ini'),
                            subtitle: const Text('Tandai jika memang tidak ada penjualan (NOSELL).'),
                          ),
                        ),
                      if (_rows.isEmpty && !_nihil)
                        const EmptyState(text: 'Belum ada penjualan', icon: Icons.receipt_long),
                      for (final r in _rows)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: Icon(r['tipe'] == 'HP' ? Icons.smartphone : Icons.watch),
                            title: Text('${r['nama_produk']}'),
                            subtitle: Text([
                              'x${r['qty']} · ${rupiah(toNum(r['subtotal']))}',
                              if (r['kategori_user'] != null) '${r['kategori_user']}',
                              if (r['metode'] != null) '${r['metode']} ${r['cara_bayar'] ?? ''}',
                            ].join(' · ')),
                            trailing: bolehJual
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Hapus',
                                    onPressed: () => _delete(r),
                                  )
                                : null,
                          ),
                        ),
                    ]),
                  ),
      ),
    );
  }
}
