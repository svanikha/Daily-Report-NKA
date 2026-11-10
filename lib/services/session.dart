import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils.dart';

/// Titik GPS toko. Satu toko bisa punya lebih dari satu titik (Erafone Pangkalanbun).
class StoreLocation {
  final String nama;
  final double lat;
  final double lng;
  final int radiusM;

  const StoreLocation({required this.nama, required this.lat, required this.lng, required this.radiusM});

  factory StoreLocation.fromMap(Map<String, dynamic> m) => StoreLocation(
        nama: '${m['nama'] ?? ''}',
        lat: toNum(m['lat']).toDouble(),
        lng: toNum(m['lng']).toDouble(),
        radiusM: m['radius_m'] == null ? 100 : toNum(m['radius_m']).toInt(),
      );
}

class Profile {
  final String id;
  final String nama;

  /// pc, tl, trainer, pic
  final String role;
  final int? storeId;
  final String toko;
  final int? areaId;
  final String area;
  final String email;
  final double? storeLat;
  final double? storeLng;
  final int radiusM;
  final List<StoreLocation> lokasi;

  const Profile({
    required this.id,
    required this.nama,
    required this.role,
    this.storeId,
    required this.toko,
    this.areaId,
    this.area = '',
    required this.email,
    this.storeLat,
    this.storeLng,
    this.radiusM = 100,
    this.lokasi = const [],
  });

  bool get isPc => role == 'pc';
  bool get isTl => role == 'tl';
  bool get isTrainer => role == 'trainer';
  bool get isPic => role == 'pic';

  /// Label peran untuk tampilan.
  String get roleLabel => switch (role) {
        'pc' => 'Product Consultant',
        'tl' => 'Tim Leader',
        'trainer' => 'Trainer',
        'pic' => 'PIC NKA',
        _ => role,
      };

  // Nama lama dari Daily Report OS (dipakai layar OS yang masih disimpan sebagai referensi).
  bool get isAdmin => isPic;
  bool get isSupport => isTl || isTrainer;

  /// TL, Trainer, dan PIC memakai beranda atasan (bukan beranda PC).
  bool get usesAdminHome => !isPc;
  bool get hasStoreLocation => storeLat != null && storeLng != null;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        nama: (m['nama'] ?? '') as String,
        role: (m['role'] ?? 'pc') as String,
        storeId: m['store_id'] == null ? null : toNum(m['store_id']).toInt(),
        toko: (m['toko'] ?? '') as String,
        areaId: m['area_id'] == null ? null : toNum(m['area_id']).toInt(),
        area: (m['area'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        storeLat: m['store_lat'] == null ? null : toNum(m['store_lat']).toDouble(),
        storeLng: m['store_lng'] == null ? null : toNum(m['store_lng']).toDouble(),
        radiusM: m['radius_m'] == null ? 100 : toNum(m['radius_m']).toInt(),
        lokasi: [for (final x in asList(m['lokasi'])) StoreLocation.fromMap(x)],
      );
}

class Session {
  static Profile? current;

  static SupabaseClient get db => Supabase.instance.client;

  static Future<Profile?> load() async {
    if (db.auth.currentSession == null) {
      current = null;
      return null;
    }
    final res = await db.rpc('my_profile');
    if (res == null) {
      current = null;
      return null;
    }
    current = Profile.fromMap(asMap(res));
    return current;
  }
}
