import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../utils.dart';
import 'location_service.dart';
import 'session.dart';

/// foto = foto asli (selfie leasing, checklist toko): diberi lokasi.
/// screenshot = bukti sosmed: tanpa lokasi.
enum PhotoKind { foto, screenshot }

const flagLabel = {
  'di_luar_toko': 'Di luar toko',
  'lokasi_tidak_tersedia': 'Lokasi tidak tersedia',
  'jam_tidak_sesuai': 'Jam HP tidak sesuai',
};

class PickedPhoto {
  final Uint8List bytes;
  final String sumber; // kamera | galeri
  final DateTime waktuAmbil; // WIB naif
  final double? lat;
  final double? lng;
  final int? jarakToko;
  final bool metadataValid;
  final List<String> flags;

  const PickedPhoto(
    this.bytes,
    this.sumber, {
    required this.waktuAmbil,
    this.lat,
    this.lng,
    this.jarakToko,
    this.metadataValid = true,
    this.flags = const [],
  });
}

class PhotoRejected implements Exception {
  final String message;
  const PhotoRejected(this.message);
  @override
  String toString() => message;
}

/// Membaca tanggal pengambilan dari metadata EXIF (format "2026:11:05 14:30:00").
DateTime? _exifDate(Uint8List raw) {
  try {
    final ex = img.decodeJpgExif(raw);
    if (ex == null) return null;
    final v = ex.exifIfd['DateTimeOriginal'] ?? ex.exifIfd['DateTimeDigitized'] ?? ex.imageIfd['DateTime'];
    if (v == null) return null;
    final m = RegExp(r'(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):?(\d{2})?').firstMatch(v.toString());
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.tryParse(m.group(6) ?? '0') ?? 0,
    );
  } catch (_) {
    return null;
  }
}

/// Tanggal dari nama file screenshot, misal Screenshot_20261105-143000.jpg.
DateTime? _nameDate(String name) {
  final m = RegExp(r'(20\d{2})[-_]?(\d{2})[-_]?(\d{2})').firstMatch(name);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// Dijalankan di isolate terpisah: perkecil foto dan tempel watermark (beberapa baris).
Uint8List _processPhoto(Map<String, dynamic> a) {
  final raw = a['bytes'] as Uint8List;
  final lines = (a['lines'] as List).cast<String>();
  var im = img.decodeImage(raw);
  if (im == null) return raw;
  im = img.bakeOrientation(im);
  if (im.width > 1280 || im.height > 1280) {
    im = im.width >= im.height ? img.copyResize(im, width: 1280) : img.copyResize(im, height: 1280);
  }
  const lineH = 30;
  final barH = lines.length * lineH + 12;
  img.fillRect(
    im,
    x1: 0,
    y1: im.height - barH,
    x2: im.width,
    y2: im.height,
    color: img.ColorRgba8(0, 0, 0, 170),
  );
  for (var i = 0; i < lines.length; i++) {
    img.drawString(
      im,
      lines[i],
      font: img.arial24,
      x: 10,
      y: im.height - barH + 6 + i * lineH,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  return img.encodeJpg(im, quality: 75);
}

DateTime? _exifInIsolate(Uint8List raw) => _exifDate(raw);

class PhotoService {
  static const bucket = 'bukti';

  /// Selisih jam HP dengan server dalam menit (null jika tidak bisa dicek).
  static Future<int?> _clockDiffMinutes() async {
    try {
      final res = await Session.db.rpc('server_now').timeout(const Duration(seconds: 6));
      final server = DateTime.parse('$res').toUtc();
      return DateTime.now().toUtc().difference(server).inMinutes.abs();
    } catch (_) {
      return null;
    }
  }

  /// Memilih foto, memvalidasi tanggal, membaca lokasi, lalu menempel watermark.
  /// [label] tampil di watermark (misal nama leasing atau item checklist).
  static Future<PickedPhoto?> pick(
    BuildContext context, {
    bool selfie = false,
    required String label,
    PhotoKind kind = PhotoKind.foto,
    bool cameraOnly = false,
  }) async {
    final pc = Session.current;
    ImageSource? source = cameraOnly ? ImageSource.camera : null;
    source ??= await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: Text(selfie ? 'Kamera (selfie)' : 'Kamera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(kind == PhotoKind.screenshot ? 'Galeri / screenshot' : 'Galeri (hanya foto hari ini)'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return null;

    // Ambil file asli (tanpa resize) agar metadata EXIF tetap utuh.
    final x = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
    );
    if (x == null) return null;
    final raw = await x.readAsBytes();
    final fromCamera = source == ImageSource.camera;
    final today = wibToday();

    // 1. Validasi tanggal
    var waktuAmbil = wibNow();
    var metadataValid = true;
    if (!fromCamera) {
      final exif = await compute(_exifInIsolate, raw);
      if (kind == PhotoKind.foto) {
        if (exif == null) {
          throw const PhotoRejected('Foto ditolak: metadata tanggal tidak ditemukan. Gunakan foto asli dari kamera.');
        }
        if (!isSameDay(dateOnly(exif), today)) {
          throw PhotoRejected('Foto ditolak: foto diambil ${tgl(exif)}. Hanya foto hari ini yang bisa diupload.');
        }
        waktuAmbil = exif;
      } else {
        final d = exif ?? _nameDate(x.name);
        if (d != null && !isSameDay(dateOnly(d), today)) {
          throw const PhotoRejected('Hanya screenshot hari ini yang bisa diupload.');
        }
        metadataValid = d != null;
        if (exif != null) waktuAmbil = exif;
      }
    }

    // 2. Lokasi (hanya foto asli)
    final flags = <String>[];
    LocationResult? loc;
    if (kind == PhotoKind.foto) {
      try {
        loc = await LocationService.current();
      } on LocationException catch (e) {
        if (e.gpsOff && context.mounted) {
          final open = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('GPS mati'),
              content: const Text('Nyalakan lokasi (GPS) agar lokasi toko tertempel di foto.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Lanjut tanpa lokasi')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka pengaturan')),
              ],
            ),
          );
          if (open == true) {
            await LocationService.openSettings();
            return null;
          }
        }
      } catch (_) {
        // Timeout atau error lain: foto tetap bisa disimpan, tetapi ditandai.
      }
      if (loc == null) {
        flags.add('lokasi_tidak_tersedia');
      } else if (loc.jarakToko != null && loc.jarakToko! > (pc?.radiusM ?? 100)) {
        flags.add('di_luar_toko');
      }
    }

    // 3. Jam HP dibandingkan dengan server
    final diff = await _clockDiffMinutes();
    if (diff != null && diff > 15) flags.add('jam_tidak_sesuai');

    // 4. Watermark
    final lines = <String>[
      '${DateFormat('dd/MM/yyyy HH:mm').format(waktuAmbil)} WIB${label.isNotEmpty ? ' - $label' : ''}',
      if (pc != null) '${pc.nama} - ${pc.toko.replaceFirst('OPPO Store - ', '')}',
      if (kind == PhotoKind.foto)
        loc == null
            ? 'Lokasi tidak tersedia'
            : '${loc.lat.toStringAsFixed(6)}, ${loc.lng.toStringAsFixed(6)}'
                '${loc.jarakToko != null ? ' - ${angka(loc.jarakToko!)} m dari toko' : ''}',
    ];
    final processed = await compute(_processPhoto, <String, dynamic>{'bytes': raw, 'lines': lines});
    return PickedPhoto(
      processed,
      fromCamera ? 'kamera' : 'galeri',
      waktuAmbil: waktuAmbil,
      lat: loc?.lat,
      lng: loc?.lng,
      jarakToko: loc?.jarakToko,
      metadataValid: metadataValid,
      flags: flags,
    );
  }

  /// Upload ke storage, mengembalikan path file.
  static Future<String> upload(String pcId, Uint8List bytes) async {
    final path = '$pcId/${todayStr()}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await Session.db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  /// Upload semua foto lalu catat di tabel photos.
  static Future<void> saveAll({
    required String pcId,
    required String refTabel,
    required String refId,
    required List<PickedPhoto> photos,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (final p in photos) {
      final path = await upload(pcId, p.bytes);
      rows.add({
        'pc_id': pcId,
        'ref_tabel': refTabel,
        'ref_id': refId,
        'path': path,
        'sumber': p.sumber,
        'waktu_ambil': wibToUtcIso(p.waktuAmbil),
        'latitude': p.lat,
        'longitude': p.lng,
        'jarak_toko_m': p.jarakToko,
        'metadata_valid': p.metadataValid,
        'flags': p.flags,
      });
    }
    if (rows.isNotEmpty) await Session.db.from('photos').insert(rows);
  }

  static Future<String> signedUrl(String path) =>
      Session.db.storage.from(bucket).createSignedUrl(path, 3600);
}
