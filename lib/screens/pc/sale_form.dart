import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/pickers.dart';
import '../../widgets/widgets.dart';

class SaleForm extends StatefulWidget {
  final Profile pc;
  final String tipe; // HP | IOT
  /// Tanggal awal yang dipilih (misal dari kalender). Default hari ini.
  final DateTime? tanggal;
  const SaleForm({super.key, required this.pc, required this.tipe, this.tanggal});

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _contact;
  int _qty = 1;
  bool _busy = false;
  // Metode pembayaran (khusus HP): Cash / Kredit + leasing
  String? _metode;
  String? _leasing;
  bool get _isHp => widget.tipe == 'HP';
  late DateTime _tanggal = widget.tanggal != null ? dateOnly(widget.tanggal!) : wibToday();

  num get _harga => toNum(_product?['harga']);

  bool get _bukanHariIni => !isSameDay(_tanggal, wibToday());

  /// Penjualan HP/IoT boleh untuk tanggal berapa pun sampai hari ini.
  Future<void> _pickTanggal() async {
    final today = wibToday();
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal.isAfter(today) ? today : _tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: today,
      helpText: 'Tanggal penjualan',
    );
    if (d != null) setState(() => _tanggal = dateOnly(d));
  }

  Future<void> _pickProduct() async {
    final p = await showProductPicker(context, tipe: widget.tipe);
    if (p != null) setState(() => _product = p);
  }

  Future<void> _pickContact() async {
    final c = await showContactPicker(context, widget.pc.id);
    if (c != null) setState(() => _contact = c);
  }

  Future<void> _save() async {
    final p = _product;
    if (p == null) {
      showMsg(context, 'Pilih produk terlebih dahulu');
      return;
    }
    if (_isHp && _metode == null) {
      showMsg(context, 'Pilih metode pembayaran: Cash atau Kredit');
      return;
    }
    if (_isHp && _leasing == null) {
      showMsg(context, _metode == 'Kredit' ? 'Pilih leasing / platform kredit' : 'Pilih cara bayar cash: Transfer, Tunai, atau OMO');
      return;
    }
    if (_tanggal.isAfter(wibToday())) {
      showMsg(context, 'Tanggal penjualan tidak boleh melewati hari ini');
      return;
    }
    if (_bukanHariIni) {
      final ok = await confirmDialog(context, 'Simpan untuk tanggal lain?',
          'Penjualan ini akan dicatat untuk ${hariTgl(_tanggal)}, bukan hari ini.', yes: 'Simpan');
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await Session.db.from('sales').insert({
        'pc_id': widget.pc.id,
        'tanggal': ymd(_tanggal),
        'product_id': p['id'],
        'tipe': widget.tipe,
        'nama_produk': p['nama'],
        'grup': p['grup'],
        'qty': _qty,
        'harga': p['harga'],
        'contact_id': _contact?['id'],
        if (_isHp) 'metode': _metode,
        if (_isHp) 'leasing': _leasing,
      });
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
      appBar: AppBar(title: Text(widget.tipe == 'HP' ? 'Penjualan HP' : 'Penjualan IoT')),
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
          Text('${_product!['grup']}', style: t.bodySmall),
        ],
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Jumlah (qty)', style: TextStyle(fontWeight: FontWeight.w600))),
          IconButton.outlined(
            onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 48, child: Text('$_qty', textAlign: TextAlign.center, style: t.titleLarge)),
          IconButton.outlined(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Harga jual (dari master, hanya RBM yang bisa ubah)'),
          child: Text(_product == null ? '-' : rupiah(_harga)),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Subtotal'),
            trailing: Text(rupiah(_harga * _qty), style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        if (_isHp) ...[
          const SizedBox(height: 16),
          const Text('Metode pembayaran *', style: TextStyle(fontWeight: FontWeight.w600)),
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
              _leasing = null;
            }),
          ),
          if (_metode != null) ...[
            const SizedBox(height: 12),
            Text(_metode == 'Kredit' ? 'Leasing / platform kredit *' : 'Cara bayar cash *',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in _metode == 'Kredit' ? kreditViaList : cashViaList)
                ChoiceChip(label: Text(l), selected: _leasing == l, onSelected: (_) => setState(() => _leasing = l)),
            ]),
          ],
        ],
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickContact,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Konsumen dari Database (opsional)',
              suffixIcon: _contact != null
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _contact = null))
                  : const Icon(Icons.person_search),
            ),
            child: Text(_contact == null ? 'Pilih konsumen' : '${_contact!['nama']} · ${_contact!['no_hp']}'),
          ),
        ),
        if (_contact != null) ...[
          const SizedBox(height: 4),
          Text('Status konsumen otomatis menjadi Closing.', style: t.bodySmall),
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
