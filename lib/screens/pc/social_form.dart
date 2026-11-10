import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';

class SocialForm extends StatefulWidget {
  final Profile pc;
  const SocialForm({super.key, required this.pc});

  @override
  State<SocialForm> createState() => _SocialFormState();
}

class _SocialFormState extends State<SocialForm> {
  String _kode = sosmedDefs.first.kode;
  final _jumlah = TextEditingController(text: '1');
  final _link = TextEditingController();
  List<PickedPhoto> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _jumlah.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final jumlah = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (jumlah <= 0) {
      showMsg(context, 'Jumlah minimal 1');
      return;
    }
    if (_photos.isEmpty) {
      showMsg(context, 'Upload minimal 1 screenshot sebagai bukti');
      return;
    }
    if (!pcInputOpen()) {
      showMsg(context, 'Input hari ini sudah ditutup (batas pukul 23.00 WIB)');
      return;
    }
    setState(() => _busy = true);
    try {
      final link = _link.text.trim();
      final row = await Session.db
          .from('social_activities')
          .insert({
            'pc_id': widget.pc.id,
            'tanggal': todayStr(),
            'kode': _kode,
            'jumlah': jumlah,
            'link': link.isEmpty ? null : link,
          })
          .select()
          .single();
      await PhotoService.saveAll(
        pcId: widget.pc.id,
        refTabel: 'social_activities',
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
    final def = sosmedByKode(_kode)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Report sosmed')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tanggal: ${hariTgl(wibToday())}'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Aktivitas *'),
          items: [for (final d in sosmedDefs) DropdownMenuItem(value: d.kode, child: Text(d.label))],
          onChanged: (v) => setState(() => _kode = v ?? _kode),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jumlah,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Jumlah (${def.satuan}) *'),
        ),
        if (_kode.startsWith('tiktok')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Link konten (opsional)'),
          ),
        ],
        const SizedBox(height: 16),
        PhotoPickerField(
          label: 'Screenshot bukti * (kamera atau galeri)',
          photos: _photos,
          photoLabel: def.label,
          kind: PhotoKind.screenshot,
          onChanged: (p) => setState(() => _photos = p),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (_busy || _photos.isEmpty) ? null : _save,
          icon: busyIcon(_busy, Icons.cloud_upload),
          label: Text(_photos.isEmpty ? 'Upload bukti dulu' : 'Simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}
