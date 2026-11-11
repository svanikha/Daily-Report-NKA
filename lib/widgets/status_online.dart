import 'package:flutter/material.dart';

import '../services/presence_service.dart';
import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

String _jam(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

/// "10.32" untuk hari ini, "Kem 10.32" untuk kemarin, atau "11 Nov 10.32".
String waktuSingkat(DateTime wib) {
  final today = wibToday();
  final d = dateOnly(wib);
  if (isSameDay(d, today)) return _jam(wib);
  if (isSameDay(d, addDays(today, -1))) return 'kemarin ${_jam(wib)}';
  return '${tglPendek(wib)} ${_jam(wib)}';
}

/// Lampu status: hijau = online (aplikasi terbuka < 5 menit lalu), merah = tidak online / tidak login.
class LampuOnline extends StatelessWidget {
  final bool online;
  final double size;
  const LampuOnline({super.key, required this.online, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final c = online ? Colors.green.shade600 : Colors.red.shade600;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4)],
      ),
    );
  }
}

/// Teks status: "Online", "Terakhir aktif 10.32", "Sudah keluar", "Belum pernah login".
String teksStatus(StatusOnline s) {
  if (s.online) return 'Online';
  if (!s.pernahLogin) return 'Belum pernah login';
  if (!s.masihLogin) return s.lastSeen == null ? 'Tidak login' : 'Keluar · terakhir ${waktuSingkat(s.lastSeen!)}';
  return s.lastSeen == null ? 'Tidak online' : 'Terakhir aktif ${waktuSingkat(s.lastSeen!)}';
}

/// Lampu + teks status dalam satu baris.
class StatusOnlineRow extends StatelessWidget {
  final StatusOnline status;
  const StatusOnlineRow({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LampuOnline(online: status.online, size: 10),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          teksStatus(status),
          style: TextStyle(fontSize: 11, color: status.online ? Colors.green.shade800 : Colors.red.shade700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

/// Riwayat login, buka aplikasi, dan keluar satu orang (30 terakhir).
Future<void> showRiwayatLogin(BuildContext context, String profileId, String nama, StatusOnline status) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.75,
      child: _RiwayatSheet(profileId: profileId, nama: nama, status: status),
    ),
  );
}

class _RiwayatSheet extends StatefulWidget {
  final String profileId;
  final String nama;
  final StatusOnline status;
  const _RiwayatSheet({required this.profileId, required this.nama, required this.status});

  @override
  State<_RiwayatSheet> createState() => _RiwayatSheetState();
}

class _RiwayatSheetState extends State<_RiwayatSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _rows = asList(await Session.db
          .from('login_log')
          .select('jenis,waktu')
          .eq('profile_id', widget.profileId)
          .order('waktu', ascending: false)
          .limit(30));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    const info = {
      'login': (Icons.login, 'Login', Colors.green),
      'buka': (Icons.phone_android, 'Buka aplikasi', Colors.blueGrey),
      'logout': (Icons.logout, 'Keluar', Colors.red),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            LampuOnline(online: s.online, size: 14),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.nama, style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text(teksStatus(s)),
          Text('Login terakhir: ${s.lastLogin == null ? '-' : '${tgl(s.lastLogin!)} ${_jam(s.lastLogin!)} WIB'}'),
          Text('Terakhir aktif: ${s.lastSeen == null ? '-' : '${tgl(s.lastSeen!)} ${_jam(s.lastSeen!)} WIB'}'),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _rows.isEmpty
                    ? const Center(child: Text('Belum ada riwayat login'))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final w = parseWib('${r['waktu']}');
                          final x = info['${r['jenis']}'];
                          return ListTile(
                            dense: true,
                            leading: Icon(x?.$1 ?? Icons.history, color: x?.$3),
                            title: Text(x?.$2 ?? '${r['jenis']}'),
                            trailing: Text('${tglPendek(w)} ${_jam(w)}'),
                          );
                        },
                      ),
      ),
    ]);
  }
}
