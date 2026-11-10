import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/session_gate.dart';
import 'services/notif_service.dart';
import 'services/push_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  if (!kIsWeb) await NotifService.init();
  // Versi web hanya untuk dashboard admin: tanpa notifikasi HP dan push Firebase.
  if (!kIsWeb) await PushService.init();
  runApp(const DailyReportApp());
}

class DailyReportApp extends StatelessWidget {
  const DailyReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Report NKA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SessionGate(),
      // Di laptop, isi aplikasi dibatasi lebarnya agar tetap enak dibaca.
      builder: (context, child) => kIsWeb
          ? ColoredBox(
              color: const Color(0xFFE3E9E6),
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: child),
              ),
            )
          : child!,
    );
  }
}
