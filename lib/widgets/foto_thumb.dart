import 'package:flutter/material.dart';

import '../services/photo_service.dart';
import 'photo_widgets.dart';

/// Gambar kecil dari bucket bukti (signed URL disimpan sementara agar tidak diminta berulang).
class FotoThumb extends StatefulWidget {
  final String path;
  final double size;
  final VoidCallback? onTap;
  const FotoThumb({super.key, required this.path, this.size = 96, this.onTap});

  static final Map<String, String> _cache = {};

  @override
  State<FotoThumb> createState() => _FotoThumbState();
}

class _FotoThumbState extends State<FotoThumb> {
  String? _url;
  bool _gagal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = FotoThumb._cache[widget.path];
    if (c != null) {
      _url = c;
      return;
    }
    try {
      final u = await PhotoService.signedUrl(widget.path);
      FotoThumb._cache[widget.path] = u;
      if (mounted) setState(() => _url = u);
    } catch (_) {
      if (mounted) setState(() => _gagal = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget child;
    if (_gagal) {
      child = const Icon(Icons.broken_image, color: Colors.grey);
    } else if (_url == null) {
      child = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = Image.network(
        _url!,
        width: s,
        height: s,
        fit: BoxFit.cover,
        cacheWidth: (s * 3).round(),
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(width: s, height: s, color: Colors.grey.shade200, alignment: Alignment.center, child: child),
      ),
    );
  }
}

/// Buka penampil foto penuh untuk daftar foto (map berisi path, sumber, flags).
void bukaFoto(BuildContext context, List<Map<String, dynamic>> photos, String judul) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewerPage(photos: photos, title: judul)));
}
