import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../screens/izin_notif_screen.dart';
import '../screens/login_screen.dart';
import '../widgets/avatar.dart';
import '../widgets/widgets.dart';
import 'notif_service.dart';
import 'presence_service.dart';
import 'push_service.dart';
import 'session.dart';

Future<void> changePasswordDialog(BuildContext context) async {
  final a = TextEditingController();
  final b = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ganti password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'Password baru')),
        const SizedBox(height: 12),
        TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Ketik ulang')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (a.text.length < 6) {
    showMsg(context, 'Password minimal 6 karakter');
    return;
  }
  if (a.text != b.text) {
    showMsg(context, 'Konfirmasi password tidak sama');
    return;
  }
  try {
    await Session.db.auth.updateUser(UserAttributes(password: a.text));
    if (context.mounted) showMsg(context, 'Password berhasil diganti');
  } catch (e) {
    if (context.mounted) showErr(context, e);
  }
}

Future<void> logout(BuildContext context) async {
  final ok = await confirmDialog(context, 'Keluar?', 'Kamu perlu memasukkan password lagi saat masuk.', yes: 'Keluar');
  if (!ok) return;
  await NotifService.cancelAll();
  await PushService.unregister();
  await PresenceService.logout();
  await Session.db.auth.signOut();
  Session.current = null;
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

/// Tombol menu akun (foto profil, akses notifikasi, ganti password, keluar) untuk AppBar.
class AkunMenuButton extends StatelessWidget {
  const AkunMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Session.perubahan,
      builder: (context, _, __) {
        final p = Session.current;
        return PopupMenuButton<String>(
          icon: p == null ? const Icon(Icons.account_circle) : AvatarProfil(url: p.fotoUrl, nama: p.nama, radius: 15),
          tooltip: 'Akun',
          onSelected: (v) {
            if (v == 'foto') gantiFotoProfil(context);
            if (v == 'pw') changePasswordDialog(context);
            if (v == 'notif') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IzinNotifScreen()));
            if (v == 'out') logout(context);
          },
          itemBuilder: (_) => [
            if (p != null)
              PopupMenuItem<String>(
                value: 'foto',
                child: Row(children: [
                  AvatarProfil(url: p.fotoUrl, nama: p.nama, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        '${p.nama}\n${p.roleLabel}${p.isPc ? ' · ${p.toko}' : (p.area.isNotEmpty ? ' · ${p.area}' : '')}'),
                  ),
                ]),
              ),
            const PopupMenuItem(value: 'foto', child: ListTile(leading: Icon(Icons.face), title: Text('Foto profil'))),
            const PopupMenuItem(
                value: 'notif', child: ListTile(leading: Icon(Icons.notifications_active), title: Text('Akses notifikasi'))),
            const PopupMenuItem(value: 'pw', child: ListTile(leading: Icon(Icons.key), title: Text('Ganti password'))),
            const PopupMenuItem(value: 'out', child: ListTile(leading: Icon(Icons.logout), title: Text('Keluar'))),
          ],
        );
      },
    );
  }
}
