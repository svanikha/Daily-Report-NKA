import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../services/notif_service.dart';
import '../../services/push_service.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../login_screen.dart';

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
  if (Session.current?.usesAdminHome ?? false) await PushService.unregister();
  await Session.db.auth.signOut();
  Session.current = null;
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<Map<String, dynamic>> _libur = [];

  @override
  void initState() {
    super.initState();
    _loadLibur();
  }

  Future<void> _loadLibur() async {
    final p = Session.current;
    if (p == null) return;
    try {
      final rows = await Session.db
          .from('pc_day_status')
          .select('tanggal,status')
          .eq('pc_id', p.id)
          .gte('tanggal', todayStr())
          .lte('tanggal', ymd(addDays(wibToday(), 14)))
          .order('tanggal');
      if (mounted) setState(() => _libur = asList(rows));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Session.current;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Akun')),
      body: p == null
          ? const SizedBox()
          : ListView(padding: const EdgeInsets.all(12), children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(p.toko),
                ),
              ),
              const SectionHeader('Jadwal offday (14 hari ke depan)'),
              Card(
                child: _libur.isEmpty
                    ? const ListTile(title: Text('Belum ada jadwal offday dari RBM'))
                    : Column(children: [
                        for (final l in _libur)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.beach_access),
                            title: Text(hariTgl(parseDate('${l['tanggal']}'))),
                            trailing: Pill(l['status'] == 'izin' ? 'Izin' : 'Offday', color: Colors.teal),
                          ),
                      ]),
              ),
              const SectionHeader('Notifikasi'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Pengingat follow up konsumen dikirim otomatis pada H+1, H+3, H+7, dan H+30 sebagai notifikasi. '
                    'Alarm report pukul 22.00 WIB jika Report, Activity, atau Checklist belum diisi. '
                    'Di hari offday semua pengingat dan kewajiban nonaktif.',
                    style: t.bodySmall,
                  ),
                ),
              ),
              const SectionHeader('Keamanan'),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.key),
                    title: const Text('Ganti password'),
                    onTap: () => changePasswordDialog(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Keluar', style: TextStyle(color: Colors.red)),
                    onTap: () => logout(context),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Center(child: Text('Daily Report NKA · versi ${UpdateService.versionName}', style: t.bodySmall)),
            ]),
    );
  }
}
