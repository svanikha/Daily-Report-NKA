import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Master produk HP & IoT. Trainer dan PIC NKA bisa menambah produk dan mengubah harga.
/// Produk yang tidak dijual lagi dinonaktifkan (tidak dihapus) supaya riwayat penjualan tetap utuh.
class ProdukScreen extends StatefulWidget {
  const ProdukScreen({super.key});

  @override
  State<ProdukScreen> createState() => _ProdukScreenState();
}

class _ProdukScreenState extends State<ProdukScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _tipe = 'HP';
  String _q = '';

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
      _rows = asList(await Session.db.from('products').select().order('tipe').order('urutan').order('nama'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProdukForm(produk: p, tipeAwal: _tipe, grupList: _rows.map((r) => '${r['grup']}').toSet().toList()),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = _rows
        .where((r) => r['tipe'] == _tipe && (q.isEmpty || '${r['nama']} ${r['grup']}'.toLowerCase().contains(q)))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Produk & harga')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Produk baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'HP', label: Text('HP'), icon: Icon(Icons.smartphone)),
                      ButtonSegment(value: 'IOT', label: Text('IoT'), icon: Icon(Icons.watch)),
                    ],
                    selected: {_tipe},
                    onSelectionChanged: (s) => setState(() => _tipe = s.first),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari produk...', isDense: true),
                    onChanged: (v) => setState(() => _q = v.trim()),
                  ),
                  const SizedBox(height: 4),
                  const InfoBanner('Perubahan harga berlaku untuk semua toko dan tercatat di riwayat. '
                      'Penjualan yang sudah tercatat tidak ikut berubah.'),
                  for (final p in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        title: Text('${p['nama']}',
                            style: TextStyle(
                                decoration: p['aktif'] == true ? null : TextDecoration.lineThrough,
                                color: p['aktif'] == true ? null : Colors.grey)),
                        subtitle: Text([
                          '${p['grup']}',
                          if (p['fokus'] != null) 'Fokus ${p['fokus']}',
                          if (p['aktif'] != true) 'Nonaktif',
                        ].join(' · ')),
                        trailing: Text(rupiah(toNum(p['harga'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => _edit(p),
                      ),
                    ),
                ]),
    );
  }
}

class _ProdukForm extends StatefulWidget {
  final Map<String, dynamic>? produk;
  final String tipeAwal;
  final List<String> grupList;
  const _ProdukForm({required this.produk, required this.tipeAwal, required this.grupList});

  @override
  State<_ProdukForm> createState() => _ProdukFormState();
}

class _ProdukFormState extends State<_ProdukForm> {
  late final _nama = TextEditingController(text: '${widget.produk?['nama'] ?? ''}');
  late final _grup = TextEditingController(text: '${widget.produk?['grup'] ?? ''}');
  late final _harga = TextEditingController(text: widget.produk == null ? '' : '${toNum(widget.produk!['harga']).toInt()}');
  late String _tipe = '${widget.produk?['tipe'] ?? widget.tipeAwal}';
  late String? _fokus = widget.produk?['fokus'] as String?;
  late bool _aktif = widget.produk?['aktif'] != false;
  bool _busy = false;

  @override
  void dispose() {
    _nama.dispose();
    _grup.dispose();
    _harga.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nama = _nama.text.trim();
    final grup = _grup.text.trim();
    final harga = digitsOnly(_harga.text);
    if (nama.isEmpty || grup.isEmpty || harga <= 0) {
      showMsg(context, 'Nama, grup/seri, dan harga wajib diisi');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = {
        'tipe': _tipe,
        'nama': nama,
        'grup': grup,
        'harga': harga,
        'fokus': _tipe == 'HP' ? _fokus : null,
        'aktif': _aktif,
      };
      if (widget.produk == null) {
        await Session.db.from('products').insert({...data, 'urutan': 999});
      } else {
        await Session.db.from('products').update(data).eq('id', widget.produk!['id'] as int);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.produk == null ? 'Produk baru' : 'Ubah produk', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'HP', label: Text('HP')),
              ButtonSegment(value: 'IOT', label: Text('IoT')),
            ],
            selected: {_tipe},
            onSelectionChanged: widget.produk == null ? (s) => setState(() => _tipe = s.first) : null,
          ),
          const SizedBox(height: 12),
          TextField(controller: _nama, decoration: const InputDecoration(labelText: 'Nama produk *', hintText: 'A7 PRO 5G [8/256]')),
          const SizedBox(height: 12),
          TextField(
            controller: _grup,
            decoration: InputDecoration(
              labelText: _tipe == 'HP' ? 'Seri *' : 'Jenis *',
              hintText: _tipe == 'HP' ? 'A Series / Reno Series / Find Series' : 'Pad / Watch / Band / Audio',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _harga,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Harga (Rp) *', prefixText: 'Rp '),
          ),
          if (_tipe == 'HP') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _fokus,
              decoration: const InputDecoration(labelText: 'Tipe fokus'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Bukan tipe fokus')),
                DropdownMenuItem(value: 'A7 Pro', child: Text('A7 Pro')),
                DropdownMenuItem(value: 'Reno 16', child: Text('Reno 16')),
              ],
              onChanged: (v) => setState(() => _fokus = v),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _aktif,
            onChanged: (v) => setState(() => _aktif = v),
            title: const Text('Aktif dijual'),
            subtitle: const Text('Nonaktif = tidak muncul di stok dan penjualan'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: busyIcon(_busy, Icons.save),
            label: const Text('Simpan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ]),
      ),
    );
  }
}
