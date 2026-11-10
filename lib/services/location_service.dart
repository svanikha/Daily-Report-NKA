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

  static int? jarakKeToko(double lat, double lng) {
    final p = Session.current;
    if (p == null || !p.hasStoreLocation) return null;
    return Geolocator.distanceBetween(lat, lng, p.storeLat!, p.storeLng!).round();
  }

  static Future<void> openSettings() => Geolocator.openLocationSettings();
}
