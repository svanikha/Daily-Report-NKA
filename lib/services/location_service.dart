import 'package:geolocator/geolocator.dart';

import 'session.dart';

class LocationResult {
  final double lat;
  final double lng;
  final double accuracy;

  /// Jarak ke toko PC dalam meter (null jika koordinat toko belum diatur).
  final int? jarakToko;
  const LocationResult(this.lat, this.lng, this.accuracy, this.jarakToko);
}

class LocationException implements Exception {
  final String message;

  /// true jika masalahnya GPS mati (bisa dibuka lewat pengaturan lokasi).
  final bool gpsOff;
  const LocationException(this.message, {this.gpsOff = false});
  @override
  String toString() => message;
}

/// Membaca lokasi HP hanya saat dibutuhkan (tidak ada pelacakan latar belakang).
class LocationService {
  static Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('GPS mati. Nyalakan lokasi (GPS) di HP lalu coba lagi.', gpsOff: true);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw const LocationException('Izin lokasi ditolak. Izinkan lokasi untuk aplikasi ini.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationException('Izin lokasi diblokir. Buka Pengaturan aplikasi lalu izinkan Lokasi.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
    );
    return LocationResult(pos.latitude, pos.longitude, pos.accuracy, jarakKeToko(pos.latitude, pos.longitude));
  }

  /// Jarak ke titik toko terdekat (Erafone Pangkalanbun punya 2 titik).
  static int? jarakKeToko(double lat, double lng) => titikTerdekat(lat, lng)?.$1;

  /// (jarak meter, titik) ke titik toko PC yang paling dekat.
  static (int, StoreLocation)? titikTerdekat(double lat, double lng) {
    final p = Session.current;
    if (p == null || p.lokasi.isEmpty) return null;
    (int, StoreLocation)? best;
    for (final l in p.lokasi) {
      final d = Geolocator.distanceBetween(lat, lng, l.lat, l.lng).round();
      if (best == null || d < best.$1) best = (d, l);
    }
    return best;
  }

  /// Radius titik toko terdekat (default 100 m).
  static int radiusTerdekat(double lat, double lng) => titikTerdekat(lat, lng)?.$2.radiusM ?? 100;

  static Future<void> openSettings() => Geolocator.openLocationSettings();
}
