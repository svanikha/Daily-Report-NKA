import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Kelola akun PC: tambah, ubah nama, pindah toko, hapus, reset password.
/// PIC NKA: semua toko. TL & Trainer: hanya toko di areanya (dijaga juga di server).
class AkunPcScreen extends StatefulWidget {
  const AkunPcScreen({super.key});

  @override
  State<AkunPcScreen> createState() => _AkunPcScreenState();
}

class _AkunPcScreenState extends State<AkunPcScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _pcs = [];

  Profile get me => Session.current!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _bolehToko(Map<String, dynamic> s) => me.isPic || toNum(s['area_id']).toInt() == me.areaId;

  Future<void> _load() async {
    setState(() {
      _loading = _pcs.isEmpty && _stores.isEmpty;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('stores').select('id,nama,area_id,punya_pc,areas(nama)').eq('aktif', true).order('area_id').order('id'),
        db.from('profiles').select('id,nama,store_id,auth_uid').eq('role', 'pc').eq('aktif', true).order('nama'),
      ]);
      _stores = asList(res[0]).where(_bolehToko).toList();
      final ids = _stores.map((s) => toNum(s['id']).toInt()).toSet();
      _pcs = asList(res[1]).where((p) => ids.contains(toNum(p['store_id']).toInt())).toList();
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _form([Map<String, dynamic>? pc]) async {
    final nama = TextEditingController(text: '${pc?['nama'] ?? ''}');
    int? toko = pc == null ? null : toNum(pc['store_id']).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(pc == null ? 'Tambah PC' : 'Ubah PC'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: pc == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama PC *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: toko,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Toko *'),
              items: [
                for (final s in _stores)
                  DropdownMenuItem(
                    value: toNum(s['id']).toInt(),
                    child: Text('${s['nama']} · ${asMap(s['areas'])['nama'] ?? ''}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setD(() => toko = v),
            ),
            if (pc != null) ...[
              const SizedBox(height: 8),
              Text('Pindah toko: data penjualan lama tetap tercatat di toko lama.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = nama.text.trim();
    nama.dispose();
    if (ok != true) return;
    if (n.isEmpty || toko == null) {
      if (mounted) showMsg(context, 'Nama dan toko wajib diisi');
      return;
    }
    await _jalankan(() => Session.db.rpc('simpan_pc', params: {'p_id': pc?['id'], 'p_nama': n, 'p_store': toko}),
        pc == null ? 'PC $n ditambahkan. PC membuat password sendiri saat login pertama.' : 'Data PC tersimpan');
  }

  Future<void> _reset(Map<String, dynamic> pc) async {
    final ok = await confirmDialog(context, 'Reset password ${pc['nama']}?',
        'PC akan keluar dan membuat password baru saat login berikutnya.', yes: 'Reset');
    if (!ok) return;
    await _jalankan(() => Session.db.rpc('reset_password', params: {'p_profile': pc['id']}),
        'Password ${pc['nama']} direset');
  }

  Future<void> _hapus(Map<String, dynamic> pc) async {
    final ok = await confirmDialog(
      context,
      'Hapus PC ${pc['nama']}?',
      'Akun tidak bisa login lagi dan hilang dari daftar. Riwayat penjualan dan laporan tetap tersimpan.',
      yes: 'Hapus',
    );
    if (!ok) return;
    await _jalankan(() => Session.db.rpc('hapus_pc', params: {'p_id': pc['id']}), 'PC ${pc['nama']} dihapus');
  }

  Future<void> _jalankan(Future<dynamic> Function() aksi, String pesan) async {
    setState(() => _busy = true);
    try {
      await aksi();
      await _load();
      if (mounted) showMsg(context, pesan);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(me.isPic ? 'Akun PC · semua area' : 'Akun PC · area ${me.area}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _stores.isEmpty ? null : () => _form(),
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah PC'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const InfoBanner('Ketuk PC untuk mengubah nama atau memindah toko. PC baru cukup memilih namanya '
                      'di layar login lalu membuat password sendiri.'),
                  for (final s in _stores) ..._tokoSection(s),
                ]),
    );
  }

  List<Widget> _tokoSection(Map<String, dynamic> s) {
    final id = toNum(s['id']).toInt();
    final pcs = _pcs.where((p) => toNum(p['store_id']).toInt() == id).toList();
    return [
      SectionHeader('${s['nama']} · ${asMap(s['areas'])['nama'] ?? ''}'),
      if (pcs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s['punya_pc'] == false ? 'Toko non PC (diinput TL)' : 'Belum ada PC',
              style: TextStyle(color: Colors.grey.shade700)),
        ),
      for (final p in pcs)
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text('${p['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(p['auth_uid'] == null ? 'Belum membuat password' : 'Sudah aktif login'),
            onTap: _busy ? null : () => _form(p),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) {
                if (v == 'ubah') _form(p);
                if (v == 'reset') _reset(p);
                if (v == 'hapus') _hapus(p);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'ubah', child: Text('Ubah nama / pindah toko')),
                if (p['auth_uid'] != null) const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                const PopupMenuItem(value: 'hapus', child: Text('Hapus PC')),
              ],
            ),
          ),
        ),
    ];
  }
}
