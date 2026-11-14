import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/pickers.dart';
import '../../widgets/widgets.dart';

/// Input penjualan OPPO untuk satu toko. Dipakai PC (tokonya) dan TL (toko di areanya).
/// Harga diambil dari master produk (dijaga juga di server).
class SaleForm extends StatefulWidget {
  final TokoHari toko;
  final String tipe; // HP | IOT

  /// Diisi untuk mengubah penjualan yang sudah ada (baris tabel sales).
  final Map<String, dynamic>? sale;
  const SaleForm({super.key, required this.toko, required this.tipe, this.sale});

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  Map<String, dynamic>? _product;
  int _qty = 1;
  bool _busy = false;
  String? _metode; // Cash | Kredit
  String? _caraBayar;
  String? _kategori; // Walk-in | Databased | Online
  late DateTime _tanggal = widget.toko.tanggal;

  bool get _ubah => widget.sale != null;

  @override
  void initState() {
    super.initState();
    final s = widget.sale;
    if (s != null) {
      _product = {'id': s['product_id'], 'nama': s['nama_produk'], 'harga': s['harga'], 'grup': s['grup']};
      _qty = toNum(s['qty']).toInt();
      _metode = s['metode'] as String?;
      _caraBayar = s['cara_bayar'] as String?;
      _kategori = s['kategori_user'] as String?;
      _tanggal = parseDate('${s['tanggal']}');
    }
  }

  /// PC hanya boleh tanggal 1 s.d. hari ini di bulan berjalan (dijaga juga di server).
  DateTime get _tanggalAwal {
    final today = wibToday();
    return (Session.current?.isPc ?? false) ? DateTime(today.year, today.month, 1) : DateTime(2026, 1, 1);
  }

  bool get _isHp => widget.tipe == 'HP';
  num get _harga => toNum(_product?['harga']);
  bool get _bukanHariIni => !isSameDay(_tanggal, wibToday());

  Future<void> _pickTanggal() async {
    final today = wibToday();
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal.isAfter(today) ? today : (_tanggal.isBefore(_tanggalAwal) ? _tanggalAwal : _tanggal),
      firstDate: _tanggalAwal,
      lastDate: today,
      helpText: 'Tanggal penjualan',
    );
    if (d != null) setState(() => _tanggal = dateOnly(d));
  }

  Future<void> _pickProduct() async {
    final p = await showProductPicker(context, tipe: widget.tipe);
    if (p != null) setState(() => _product = p);
  }

  Future<void> _save() async {
    final p = _product;
    if (p == null) {
      showMsg(context, 'Pilih produk terlebih dahulu');
      return;
    }
    if (_kategori == null) {
      showMsg(context, 'Pilih kategori user: Walk-in, Databased, atau Online');
      return;
    }
    if (_isHp && _metode == null) {
      showMsg(context, 'Pilih metode pembayaran: Cash atau Kredit');
      return;
    }
    if (_metode != null && _caraBayar == null) {
      showMsg(context, _metode == 'Kredit' ? 'Pilih leasing / platform kredit' : 'Pilih cara bayar cash: Transfer atau Tunai');
      return;
    }
    if (_bukanHariIni && !_ubah) {
      final ok = await confirmDialog(context, 'Simpan untuk tanggal lain?',
          'Penjualan ini akan dicatat untuk ${hariTgl(_tanggal)}, bukan hari ini.', yes: 'Simpan');
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      final me = Session.current!;
      if (_ubah) {
        await Session.db.from('sales').update({
          'tanggal': ymd(_tanggal),
          'product_id': p['id'],
          'nama_produk': p['nama'],
          'grup': p['grup'],
          'qty': _qty,
          'harga': p['harga'],
          'metode': _metode,
          'cara_bayar': _caraBayar,
          'kategori_user': _kategori,
        }).eq('id', '${widget.sale!['id']}');
        if (mounted) Navigator.pop(context, true);
        return;
      }
      await Session.db.from('sales').insert({
        'store_id': widget.toko.storeId,
        'pc_id': me.isPc ? me.id : null,
        'tanggal': ymd(_tanggal),
        'product_id': p['id'],
        'tipe': widget.tipe,
        'nama_produk': p['nama'],
        'grup': p['grup'],
        'qty': _qty,
        'harga': p['harga'],
        'metode': _metode,
        'cara_bayar': _caraBayar,
        'kategori_user': _kategori,
      });
      // Ada penjualan: tanda "tidak ada penjualan" untuk tanggal itu tidak berlaku lagi.
      try {
        await Session.db
            .from('checkins')
            .delete()
            .eq('store_id', widget.toko.storeId)
            .eq('tanggal', ymd(_tanggal))
            .eq('modul', 'penjualan');
      } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_ubah ? 'Ubah penjualan' : 'Penjualan'} ${_isHp ? 'HP' : 'IoT'}'),
          Text(widget.toko.toko, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InkWell(
          onTap: _pickTanggal,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Tanggal penjualan *', suffixIcon: Icon(Icons.calendar_month)),
            child: Text(hariTgl(_tanggal), style: TextStyle(fontWeight: _bukanHariIni ? FontWeight.bold : null)),
          ),
        ),
        if (_bukanHariIni) ...[
          const SizedBox(height: 4),
          Text('Bukan hari ini: penjualan dicatat untuk tanggal yang dipilih.',
              style: t.bodySmall?.copyWith(color: Colors.orange.shade800)),
        ],
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickProduct,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Produk *', suffixIcon: Icon(Icons.arrow_drop_down)),
            child: Text(_product == null ? 'Pilih produk' : '${_product!['nama']}'),
          ),
        ),
        if (_product != null) ...[
          const SizedBox(height: 4),
          Text('${_product!['grup']}${_product!['fokus'] != null ? ' · tipe fokus ${_product!['fokus']}' : ''}',
              style: t.bodySmall),
        ],
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Jumlah (qty)', style: TextStyle(fontWeight: FontWeight.w600))),
          IconButton.outlined(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 48, child: Text('$_qty', textAlign: TextAlign.center, style: t.titleLarge)),
          IconButton.outlined(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Harga jual (dari master produk)'),
          child: Text(_product == null ? '-' : rupiah(_harga)),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Subtotal'),
            trailing: Text(rupiah(_harga * _qty), style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Kategori user *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'Walk-in', label: Text('Walk-in'), icon: Icon(Icons.directions_walk)),
            ButtonSegment(value: 'Databased', label: Text('Databased'), icon: Icon(Icons.contacts)),
            ButtonSegment(value: 'Online', label: Text('Online'), icon: Icon(Icons.language)),
          ],
          selected: {if (_kategori != null) _kategori!},
          onSelectionChanged: (s) => setState(() => _kategori = s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: 16),
        Text(_isHp ? 'Metode pembayaran *' : 'Metode pembayaran (opsional)', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'Cash', label: Text('Cash'), icon: Icon(Icons.payments)),
            ButtonSegment(value: 'Kredit', label: Text('Kredit'), icon: Icon(Icons.credit_card)),
          ],
          selected: {if (_metode != null) _metode!},
          onSelectionChanged: (s) => setState(() {
            _metode = s.isEmpty ? null : s.first;
            _caraBayar = null;
          }),
        ),
        if (_metode != null) ...[
          const SizedBox(height: 12),
          Text(_metode == 'Kredit' ? 'Leasing / platform kredit *' : 'Cara bayar cash *',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in _metode == 'Kredit' ? kreditViaList : cashViaList)
              ChoiceChip(label: Text(l), selected: _caraBayar == l, onSelected: (_) => setState(() => _caraBayar = l)),
          ]),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: busyIcon(_busy, Icons.save),
          label: const Text('Simpan penjualan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}
