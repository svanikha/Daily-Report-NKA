import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Stok pagi: semua produk aktif, angka awal = stok terakhir toko. PC cukup mengubah angkanya.
class StokScreen extends StatefulWidget {
  final TokoHari toko;
  const StokScreen({super.key, required this.toko});

  @override
  State<StokScreen> createState() => _StokScreenState();
}

class _StokScreenState extends State<StokScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _products = [];
  final Map<int, TextEditingController> _c = {};
  DateTime? _waktuInput; // jam input pertama hari ini (WIB)
  String? _sumberAwal; // tanggal stok terakhir yang dipakai sebagai angka awal
  String _q = '';

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('products').select('id,tipe,nama,grup,fokus').eq('aktif', true).order('tipe').order('urutan').order('nama'),
        db.from('stock_daily').select('product_id,qty,waktu_input').eq('store_id', t.storeId).eq('tanggal', t.tgl),
        db
            .from('stock_daily')
            .select('tanggal')
            .eq('store_id', t.storeId)
            .lt('tanggal', t.tgl)
            .order('tanggal', ascending: false)
            .limit(1),
      ]);
      _products = asList(res[0]);
      final today = asList(res[1]);
      var qty = <int, int>{};
      if (today.isNotEmpty) {
        for (final r in today) {
          qty[toNum(r['product_id']).toInt()] = toNum(r['qty']).toInt();
        }
        final times = today.map((r) => parseWib('${r['waktu_input']}')).toList()..sort();
        _waktuInput = times.first;
        _sumberAwal = null;
      } else {
        _waktuInput = null;
        final last = asList(res[2]);
        if (last.isNotEmpty) {
          _sumberAwal = '${last.first['tanggal']}';
          final rows = asList(await db
              .from('stock_daily')
              .select('product_id,qty')
              .eq('store_id', t.storeId)
              .eq('tanggal', _sumberAwal!));
          qty = {for (final r in rows) toNum(r['product_id']).toInt(): toNum(r['qty']).toInt()};
        }
      }
      for (final c in _c.values) {
        c.dispose();
      }
      _c.clear();
      for (final p in _products) {
        final id = toNum(p['id']).toInt();
        _c[id] = TextEditingController(text: '${qty[id] ?? 0}');
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  int _val(int id) => int.tryParse(_c[id]?.text.trim() ?? '') ?? 0;

  void _step(int id, int d) {
    final v = (_val(id) + d).clamp(0, 9999);
    setState(() => _c[id]!.text = '$v');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final me = Session.current!;
      final rows = [
        for (final p in _products)
          {
            'store_id': t.storeId,
            'tanggal': t.tgl,
            'product_id': p['id'],
            'qty': _val(toNum(p['id']).toInt()),
            'diinput_oleh': me.id,
          }
      ];
      await Session.db.from('stock_daily').upsert(rows, onConflict: 'store_id,tanggal,product_id');
      if (!mounted) return;
      showMsg(context, 'Stok tersimpan');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final q = _q.toLowerCase();
    final items = _products.where((p) => q.isEmpty || '${p['nama']} ${p['grup']}'.toLowerCase().contains(q)).toList();
    final kosongFokus = _products
        .where((p) => p['fokus'] != null && _val(toNum(p['id']).toInt()) == 0)
        .map((p) => '${p['nama']}')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Update stok'),
          Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      bottomNavigationBar: _loading || _error != null || !boleh
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: Text(_waktuInput == null ? 'Simpan stok' : 'Simpan koreksi stok'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
                  if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                  if (_waktuInput != null)
                    InfoBanner(
                      'Stok sudah diisi pukul ${jamMenit(_waktuInput!)} WIB. Bisa diupdate lagi kapan saja hari ini.',
                      icon: Icons.check_circle,
                      color: Colors.green.shade700,
                    )
                  else
                    InfoBanner(
                      _sumberAwal == null
                          ? 'Isi jumlah stok setiap produk.'
                          : 'Angka awal = stok ${tgl(parseDate(_sumberAwal!))}. Ubah yang berbeda saja.',
                    ),
                  if (kosongFokus.isNotEmpty)
                    InfoBanner('Stok kosong tipe fokus: ${kosongFokus.join(', ')}',
                        icon: Icons.report_gmailerrorred, color: Colors.red.shade700),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari produk...', isDense: true),
                    onChanged: (v) => setState(() => _q = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  ..._daftar(items, boleh),
                ]),
    );
  }

  /// Daftar produk dengan judul per grup (A Series, Reno Series, Pad, dst).
  List<Widget> _daftar(List<Map<String, dynamic>> items, bool boleh) {
    final out = <Widget>[];
    String? grup;
    for (final p in items) {
      final g = '${p['tipe']}|${p['grup']}';
      if (g != grup) {
        grup = g;
        out.add(SectionHeader('${p['tipe'] == 'HP' ? 'HP' : 'IoT'} · ${p['grup']}'));
      }
      out.add(_row(p, boleh));
    }
    return out;
  }

  Widget _row(Map<String, dynamic> p, bool boleh) {
    final id = toNum(p['id']).toInt();
    final fokus = p['fokus'] != null;
    final nol = _val(id) == 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['nama']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (fokus)
                Text('Tipe fokus ${p['fokus']}${nol ? ' · KOSONG' : ''}',
                    style: TextStyle(fontSize: 11, color: nol ? Colors.red.shade700 : Colors.green.shade700)),
            ]),
          ),
          IconButton(onPressed: boleh ? () => _step(id, -1) : null, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _c[id],
              enabled: boleh,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(onPressed: boleh ? () => _step(id, 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
      ),
    );
  }
}
