import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Khusus PIC NKA: daftar akun TL dan Trainer, dengan reset password.
/// Setelah direset, pemilik akun membuat password baru saat login berikutnya.
class AkunAtasanScreen extends StatefulWidget {
  const AkunAtasanScreen({super.key});

  @override
  State<AkunAtasanScreen> createState() => _AkunAtasanScreenState();
}

class _AkunAtasanScreenState extends State<AkunAtasanScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      _rows = asList(await Session.db
          .from('profiles')
          .select('id,nama,role,auth_uid,area_id,areas(nama)')
          .inFilter('role', ['tl', 'trainer'])
          .eq('aktif', true)
          .order('area_id')
          .order('role')
          .order('nama'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reset(Map<String, dynamic> p) async {
    final peran = p['role'] == 'tl' ? 'TL' : 'Trainer';
    final ok = await confirmDialog(
      context,
      'Reset password ${p['nama']}?',
      '$peran ini akan keluar dari aplikasi, lalu membuat password baru sendiri saat login berikutnya '
          '(pilih namanya di layar login, isi password baru 2x).',
      yes: 'Reset',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await Session.db.rpc('reset_password', params: {'p_profile': p['id']});
      await _load();
      if (mounted) showMsg(context, 'Password ${p['nama']} direset');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[
      if (_busy) const LinearProgressIndicator(),
      const InfoBanner('Reset password jika TL atau Trainer lupa password. Akunnya keluar dari aplikasi, '
          'lalu membuat password baru sendiri saat login berikutnya.'),
    ];
    String? area;
    for (final p in _rows) {
      final a = '${asMap(p['areas'])['nama'] ?? '-'}';
      if (a != area) {
        area = a;
        out.add(SectionHeader('Area $a'));
      }
      final sudah = p['auth_uid'] != null;
      out.add(Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          leading: CircleAvatar(child: Icon(p['role'] == 'tl' ? Icons.supervisor_account : Icons.school)),
          title: Text('${p['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${p['role'] == 'tl' ? 'Tim Leader' : 'Trainer'} · '
              '${sudah ? 'sudah aktif login' : 'belum membuat password'}'),
          trailing: sudah
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : () => _reset(p),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Reset'),
                )
              : null,
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Akun TL & Trainer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: out)),
    );
  }
}
