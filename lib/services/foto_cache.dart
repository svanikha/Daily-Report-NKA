import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'photo_service.dart';

/// Foto bukti disimpan di memori HP (disk cache) dengan kunci = path di storage.
/// Foto yang sudah pernah dibuka tidak diunduh ulang dari Supabase (hemat cached egress).
class FotoCache {
  static final _mgr = CacheManager(Config(
    'nka_foto',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 600,
  ));

  static final Map<String, Future<ImageProvider>> _proses = {};

  /// Gambar untuk satu path bucket "bukti".
  static Future<ImageProvider> gambar(String path) => _proses.putIfAbsent(path, () => _ambil(path));

  static Future<ImageProvider> _ambil(String path) async {
    try {
      if (kIsWeb) return NetworkImage(await PhotoService.signedUrl(path));
      final ada = await _mgr.getFileFromCache(path);
      if (ada != null) return FileImage(ada.file);
      final url = await PhotoService.signedUrl(path);
      final f = await _mgr.getSingleFile(url, key: path);
      return FileImage(f);
    } catch (e) {
      _proses.remove(path); // boleh dicoba lagi
      rethrow;
    }
  }
}
