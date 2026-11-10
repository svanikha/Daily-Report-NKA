/// Konfigurasi koneksi Supabase (project KHUSUS Daily Report NKA, terpisah dari Daily Report OS).
/// Isi dengan Project URL dan anon/publishable key dari Supabase
/// (Project Settings -> API). Anon key memang dirancang untuk ada di
/// aplikasi; keamanan data dijaga oleh Row Level Security di server.
/// Bisa juga diisi saat build lewat --dart-define=SUPABASE_URL=... dan SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://GANTI.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'GANTI_ANON_KEY',
  );

  static bool get isConfigured => !supabaseUrl.contains('GANTI') && !supabaseAnonKey.contains('GANTI');
}

/// Konfigurasi Firebase (push peringatan istirahat ke HP TL, Trainer, PIC).
/// Ambil dari Firebase Console -> Project settings -> Your apps -> Android
/// (package com.oppobigsampit.daily_report_nka). Nilai ini bukan rahasia.
/// Selama masih kosong, aplikasi tetap berjalan tanpa push notification.
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty;
}
