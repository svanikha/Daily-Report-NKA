import 'package:flutter/material.dart';

import '../services/foto_cache.dart';
import 'photo_widgets.dart';

/// Gambar kecil dari bucket bukti. Disimpan di memori HP, jadi tidak diunduh ulang.
class FotoThumb extends StatelessWidget {
  final String path;
  final double size;
  final VoidCallback? onTap;
  const FotoThumb({super.key, required this.path, this.size = 96, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = size;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: s,
          height: s,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: FutureBuilder<ImageProvider>(
            future: FotoCache.gambar(path),
            builder: (context, snap) {
              if (snap.hasError) return const Icon(Icons.broken_image, color: Colors.grey);
              if (!snap.hasData) {
                return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
              }
              return Image(
                image: ResizeImage(snap.data!, width: (s * 3).round()),
                width: s,
                height: s,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Buka penampil foto penuh untuk daftar foto (map berisi path, sumber, flags).
void bukaFoto(BuildContext context, List<Map<String, dynamic>> photos, String judul) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewerPage(photos: photos, title: judul)));
}
