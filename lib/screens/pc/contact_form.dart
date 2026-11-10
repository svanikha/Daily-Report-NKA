import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../data/catalog.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/pickers.dart';
import '../../widgets/widgets.dart';

class ContactForm extends StatefulWidget {
  final Profile pc;
  final Map<String, dynamic>? existing;
  const ContactForm({super.key, required this.pc, this.existing});

  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  final _form = GlobalKey<FormState>();
  late final _nama = TextEditingController(text: (widget.existing?['nama'] ?? '') as String);
  late final _hp = TextEditingController(text: (widget.existing?['no_hp'] ?? '') as String);
  late final _catatan = TextEditingController(text: (widget.existing?['catatan'] ?? '') as String);
  late String? _kat = widget.existing?['kategori'] as String?;
  late String _status = (widget.existing?['status'] ?? 'Asking') as String;
  late String? _produk = widget.existing?['produk_minat'] as String?;
  bool _busy = false;

  @override
  void dispose() {
    _nama.dispose();
    _hp.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) showMsg(context, 'Izin akses kontak ditolak');
        return;
      }
      final picked = await FlutterContacts.openExternalPick();
      if (picked == null) return;
      var full = picked;
      if (full.phones.isEmpty) {
        final f = await FlutterContacts.getContact(picked.id);
        if (f != null) full = f;
      }
      if (!mounted) return;
      var phone = full.phones.isNotEmpty ? full.phones.first.number : '';
      if (full.phones.length > 1) {
        final chosen = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Pilih nomor'),
            children: [
              for (final p in full.phones)
                SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p.number), child: Text(p.number)),
            ],
          ),
        );
        if (chosen != null) phone = chosen;
      }
      setState(() {
        _nama.text = full.displayName;
        if (phone.isNotEmpty) _hp.text = phone;
      });
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _pickProduk() async {
    final p = await showProductPicker(context);
    if (p != null) setState(() => _produk = p['nama'] as String);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_kat == null) {
      showMsg(context, 'Pilih kategori user');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = Session.db;
      final no = normalizePhone(_hp.text);
      final catatan = _catatan.text.trim();
      final data = <String, dynamic>{
        'nama': _nama.text.trim(),
        'no_hp': no,
        'kategori': _kat,
        'status': _status,
        'produk_minat': _produk,
        'catatan': catatan.isEmpty ? null : catatan,
      };
      if (widget.existing == null) {
        final dup = await db.from('contacts').select('nama').eq('pc_id', widget.pc.id).eq('no_hp', no).limit(1);
        if (dup.isNotEmpty && mounted) {
          final ok = await confirmDialog(
            context,
            'Nomor sudah ada',
            'Nomor ini sudah tersimpan atas nama ${dup.first['nama']}. Tetap simpan?',
            yes: 'Tetap simpan',
          );
          if (!ok) {
            if (mounted) setState(() => _busy = false);
            return;
          }
        }
        await db.from('contacts').insert({...data, 'pc_id': widget.pc.id});
      } else {
        await db
            .from('contacts')
            .update({...data, 'updated_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', widget.existing!['id'] as String);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Database baru' : 'Edit kontak')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.existing == null)
            OutlinedButton.icon(
              onPressed: _pickContact,
              icon: const Icon(Icons.contacts),
              label: const Text('Ambil dari Kontak HP'),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nama,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama konsumen *'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Nomor HP *', hintText: '08xxxxxxxxxx'),
            validator: (v) => normalizePhone(v ?? '').length < 10 ? 'Nomor HP tidak valid' : null,
          ),
          const SizedBox(height: 16),
          const Text('Kategori user *', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kategoriUser)
              ChoiceChip(label: Text(k), selected: _kat == k, onSelected: (_) => setState(() => _kat = k)),
          ]),
          const SizedBox(height: 16),
          const Text('Status *', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in statusUser)
              ChoiceChip(
                label: Text(s),
                selected: _status == s,
                selectedColor: statusColor(s).withValues(alpha: 0.2),
                onSelected: (_) => setState(() => _status = s),
              ),
          ]),
          const SizedBox(height: 4),
          Text(statusDesc[_status] ?? '', style: small),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickProduk,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Produk diminati (opsional)',
                suffixIcon: _produk != null
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _produk = null))
                    : const Icon(Icons.arrow_drop_down),
              ),
              child: Text(_produk ?? 'Pilih produk'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _catatan,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Catatan (kebutuhan, budget, keberatan)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: busyIcon(_busy, Icons.save),
            label: const Text('Simpan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (widget.existing == null) ...[
            const SizedBox(height: 8),
            Text('Pengingat follow up H+1, H+3, H+7, dan H+30 dibuat otomatis.', style: small, textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}
