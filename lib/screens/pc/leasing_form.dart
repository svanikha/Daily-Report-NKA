import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/pickers.dart';
import '../../widgets/widgets.dart';

class LeasingForm extends StatefulWidget {
  final Profile pc;
  const LeasingForm({super.key, required this.pc});

  @override
  State<LeasingForm> createState() => _LeasingFormState();
}

class _LeasingFormState extends State<LeasingForm> {
  String? _leasing;
  String _hasil = 'Approve';
  final _limit = TextEditingController();
  Map<String, dynamic>? _contact;
  List<PickedPhoto> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final c = await showContactPicker(context, widget.pc.id);
    if (c != null) setState(() => _contact = c);
  }

  Future<void> _save() async {
    if (_leasing == null) {
      showMsg(context, 'Pilih leasing');
      return;
    }
    final limit = digitsOnly(_limit.text);
    if (_hasil == 'Approve' && limit <= 0) {
      showMsg(context, 'Isi limit yang didapat');
      return;
    }
    if (_photos.isEmpty) {
      showMsg(context, 'Foto selfie dengan sales leasing wajib diupload');
      return;
    }
    if (!pcInputOpen()) {
      showMsg(context, 'Input hari ini sudah ditutup (batas pukul 23.00 WIB)');
      return;
    }
    setState(() => _busy = true);
    try {
      final row = await Session.db
          .from('leasing_checks')
          .insert({
            'pc_id': widget.pc.id,
            'tanggal': todayStr(),
            'leasing': _leasing,
            'hasil': _hasil,
            'limit_disetujui': _hasil == 'Approve' ? limit : null,
            'contact_id': _contact?['id'],
          })
          .select()
          .single();
      await PhotoService.saveAll(
        pcId: widget.pc.id,
        refTabel: 'leasing_checks',
        refId: row['id'] as String,
        photos: _photos,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report cek limit leasing')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tanggal: ${hariTgl(wibToday())}'),
        const SizedBox(height: 12),
        const Text('Leasing *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final l in leasingList)
            ChoiceChip(label: Text(l), selected: _leasing == l, onSelected: (_) => setState(() => _leasing = l)),
        ]),
        const SizedBox(height: 16),
        const Text('Hasil *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Approve', label: Text('Approve'), icon: Icon(Icons.check_circle)),
            ButtonSegment(value: 'Reject', label: Text('Reject'), icon: Icon(Icons.cancel)),
          ],
          selected: {_hasil},
          onSelectionChanged: (s) => setState(() => _hasil = s.first),
        ),
        if (_hasil == 'Approve') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Limit yang didapat (Rp) *', prefixText: 'Rp '),
          ),
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
            child: Text(_contact == null ? 'Pilih konsumen' : '${_contact!['nama']}'),
          ),
        ),
        const SizedBox(height: 16),
        PhotoPickerField(
          label: 'Foto selfie dengan sales leasing *',
          photos: _photos,
          max: 1,
          selfie: true,
          photoLabel: 'Leasing ${_leasing ?? ''}',
          onChanged: (p) => setState(() => _photos = p),
        ),
        const SizedBox(height: 4),
        Text('Tanggal, jam, lokasi, nama, dan toko otomatis ditempel di foto. Foto galeri harus diambil hari ini.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (_busy || _photos.isEmpty) ? null : _save,
          icon: busyIcon(_busy, Icons.cloud_upload),
          label: Text(_photos.isEmpty ? 'Upload selfie dulu' : 'Simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}
