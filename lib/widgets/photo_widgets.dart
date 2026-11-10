import 'package:flutter/material.dart';

import '../services/photo_service.dart';
import 'widgets.dart';

/// Kolom pilih foto bukti (kamera atau galeri).
class PhotoPickerField extends StatelessWidget {
  final List<PickedPhoto> photos;
  final ValueChanged<List<PickedPhoto>> onChanged;
  final int max;
  final bool selfie;
  final String label;

  /// Teks tambahan di watermark (misal nama leasing atau aktivitas).
  final String photoLabel;
  final PhotoKind kind;
  final bool cameraOnly;

  const PhotoPickerField({
    super.key,
    required this.photos,
    required this.onChanged,
    required this.label,
    required this.photoLabel,
    this.max = 5,
    this.selfie = false,
    this.kind = PhotoKind.foto,
    this.cameraOnly = false,
  });

  Future<void> _add(BuildContext context) async {
    try {
      final p = await PhotoService.pick(context, selfie: selfie, label: photoLabel, kind: kind, cameraOnly: cameraOnly);
      if (p != null) onChanged([...photos, p]);
    } on PhotoRejected catch (e) {
      if (context.mounted) await showRejected(context, e.message);
    } catch (e) {
      if (context.mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < photos.length; i++)
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(photos[i].bytes, width: 96, height: 96, fit: BoxFit.cover),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Pill(photos[i].sumber == 'kamera' ? 'Kamera' : 'Galeri', color: Colors.white),
            ),
            if (photos[i].flags.isNotEmpty)
              const Positioned(
                left: 4,
                top: 4,
                child: Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton.filled(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => onChanged([...photos]..removeAt(i)),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ]),
        if (photos.length < max)
          InkWell(
            onTap: () => _add(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(selfie ? Icons.camera_front : Icons.add_a_photo, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 4),
                const Text('Tambah foto', style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    ]);
  }
}

Future<void> showRejected(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block, color: Colors.red),
        title: const Text('Foto ditolak'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti'))],
      ),
    );

/// Pill tanda foto (Di luar toko, Lokasi tidak tersedia, Jam HP tidak sesuai).
List<Widget> photoFlagPills(dynamic flags) => [
      for (final f in (flags is List ? flags : const []))
        Pill(flagLabel['$f'] ?? '$f', color: Colors.red.shade700),
    ];

/// Halaman untuk melihat foto bukti dari storage.
class PhotoViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> photos; // berisi path, sumber
  final String title;
  const PhotoViewerPage({super.key, required this.photos, this.title = 'Foto bukti'});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  final Map<String, String> _urls = {};
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      for (final p in widget.photos) {
        final path = p['path'] as String;
        _urls[path] = await PhotoService.signedUrl(path);
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${widget.title} (${_index + 1}/${widget.photos.length})'),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : PageView.builder(
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final p = widget.photos[i];
                final url = _urls[p['path']];
                return Stack(children: [
                  Positioned.fill(
                    child: url == null
                        ? const Center(child: CircularProgressIndicator())
                        : InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    right: 12,
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      Pill(p['sumber'] == 'galeri' ? 'Dari galeri' : 'Dari kamera',
                          color: p['sumber'] == 'galeri' ? Colors.orange : Colors.lightGreenAccent),
                      for (final f in (p['flags'] is List ? p['flags'] as List : const []))
                        Pill(flagLabel['$f'] ?? '$f', color: Colors.redAccent),
                    ]),
                  ),
                ]);
              },
            ),
    );
  }
}
