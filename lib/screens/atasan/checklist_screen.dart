import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Daftar item checklist display (POSM, dummy, harga terpasang, dst).
/// TL, Trainer, dan PIC NKA bisa menambah, mengubah, mengurutkan, dan menonaktifkan item.
/// Item tidak dihapus (hanya dinonaktifkan) agar riwayat cek display lama tetap utuh.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
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
      _rows = asList(await Session.db.from('checklist_items').select().order('aktif', ascending: false).order('urutan').order('id'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _aktif => _rows.where((r) => r['aktif'] == true).toList();

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final nama = TextEditingController(text: '${item?['nama'] ?? ''}');
    final ket = TextEditingController(text: '${item?['keterangan'] ?? ''}');
    var aktif = item?['aktif'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(item == null ? 'Item checklist baru' : 'Ubah item checklist'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: item == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nama item *', hintText: 'Misal: Wobbler A7 Pro terpasang'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ket,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Keterangan (opsional)', hintText: 'Penjelasan untuk PC'),
            ),
            if (item != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: aktif,
                onChanged: (v) => setD(() => aktif = v),
                title: const Text('Aktif'),
                subtitle: const Text('Nonaktif = tidak muncul di cek display PC'),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = nama.text.trim();
    final k = ket.text.trim();
    nama.dispose();
    ket.dispose();
    if (ok != true) return;
    if (n.isEmpty) {
      if (mounted) showMsg(context, 'Nama item wajib diisi');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = {'nama': n, 'keterangan': k.isEmpty ? null : k, 'aktif': aktif};
      if (item == null) {
        final maxUrut = _rows.fold<int>(0, (a, r) => toNum(r['urutan']).toInt() > a ? toNum(r['urutan']).toInt() : a);
        await Session.db.from('checklist_items').insert({...data, 'urutan': maxUrut + 1});
      } else {
        await Session.db.from('checklist_items').update(data).eq('id', toNum(item['id']).toInt());
      }
      await _load();
      if (mounted) showMsg(context, 'Checklist tersimpan');
    } catch (e) {
      if (mounted) showErr(context, e.toString().contains('duplicate') ? 'Nama item sudah ada' : e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Tukar urutan item aktif ke-[i] dengan tetangganya ([arah] -1 naik, +1 turun).
  Future<void> _geser(int i, int arah) async {
    final list = _aktif;
    final j = i + arah;
    if (j < 0 || j >= list.length) return;
    setState(() => _busy = true);
    try {
      // Tulis ulang urutan 1..n agar rapi, dengan dua item ditukar
      final ids = list.map((r) => toNum(r['id']).toInt()).toList();
      final t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
      for (var k = 0; k < ids.length; k++) {
        await Session.db.from('checklist_items').update({'urutan': k + 1}).eq('id', ids[k]);
      }
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final aktif = _aktif;
    final nonaktif = _rows.where((r) => r['aktif'] != true).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Checklist display')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Item baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const InfoBanner('Item aktif muncul di menu Cek display semua PC, sesuai urutan di bawah. '
                      'Ketuk item untuk mengubah atau menonaktifkan.'),
                  SectionHeader('Aktif (${aktif.length})'),
                  if (aktif.isEmpty) const EmptyState(text: 'Belum ada item aktif', icon: Icons.checklist),
                  for (var i = 0; i < aktif.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                        title: Text('${aktif[i]['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: aktif[i]['keterangan'] == null ? null : Text('${aktif[i]['keterangan']}'),
                        onTap: _busy ? null : () => _edit(aktif[i]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Naik',
                            onPressed: _busy || i == 0 ? null : () => _geser(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Turun',
                            onPressed: _busy || i == aktif.length - 1 ? null : () => _geser(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ]),
                      ),
                    ),
                  if (nonaktif.isNotEmpty) ...[
                    SectionHeader('Nonaktif (${nonaktif.length})'),
                    for (final r in nonaktif)
                      Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const Icon(Icons.visibility_off, color: Colors.grey),
                          title: Text('${r['nama']}', style: const TextStyle(color: Colors.grey)),
                          subtitle: const Text('Ketuk untuk mengaktifkan lagi'),
                          onTap: _busy ? null : () => _edit(r),
                        ),
                      ),
                  ],
                ]),
    );
  }
}
