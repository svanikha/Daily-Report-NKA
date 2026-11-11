import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/presence_service.dart';
import '../services/session.dart';
import '../widgets/widgets.dart';
import 'atasan/atasan_home.dart';
import 'login_screen.dart';
import 'pc/pc_home.dart';

Widget homeFor(Profile p) {
  if (p.usesAdminHome) return const AtasanHome();
  // Versi web hanya untuk TL, Trainer, dan PIC NKA: PC memakai aplikasi HP.
  if (kIsWeb) return const WebPcBlocked();
  return PcHome(pc: p);
}

class WebPcBlocked extends StatelessWidget {
  const WebPcBlocked({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.phone_android, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Versi web hanya untuk TL, Trainer, dan PIC NKA.\nProduct Consultant silakan memakai aplikasi Daily Report NKA di HP.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Session.db.auth.signOut();
                Session.current = null;
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
            ),
          ]),
        ),
      ),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late Future<Profile?> _future = _muat();

  // Sesi login tersimpan: catat "aplikasi dibuka" untuk status online & riwayat login.
  static Future<Profile?> _muat() async {
    final p = await Session.load();
    if (p != null) PresenceService.buka();
    return p;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const Scaffold(
        body: ErrorRetryless(
          'Aplikasi belum dihubungkan ke server Supabase.\nIsi Project URL dan anon key di lib/config.dart lalu build ulang.',
        ),
      );
    }
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: ErrorRetry(
              error: 'Gagal memuat akun: ${errMsg(snap.error!)}',
              onRetry: () => setState(() => _future = _muat()),
            ),
          );
        }
        final p = snap.data;
        if (p == null) return const LoginScreen();
        return homeFor(p);
      },
    );
  }
}

class ErrorRetryless extends StatelessWidget {
  final String text;
  const ErrorRetryless(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)),
      );
}
