import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';

/// Cek display harian: checklist (POSM, dummy, harga terpasang) + foto area display OPPO.
class DisplayScreen extends StatefulWidget {
  final TokoHari toko;
  const DisplayScreen({super.key, required this.toko});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Map<int, bool> _ok = {};
  String? _reportId;
  List<Map<String, dynamic>> _fotoLama = [];
  List<PickedPhoto> _fotoBaru = [];
  final _catatan = TextEditingController();

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('checklist_items').select('id,nama,keterangan').eq('aktif', true).order('urutan'),
        db.from('display_checks').select('item_id,ok').eq('store_id', t.storeId).eq('tanggal', t.tgl),
        db.from('display_reports').select('id,catatan').eq('store_id', t.storeId).eq('tanggal', t.tgl).maybeSingle(),
      ]);
      _items = asList(res[0]);
      final checks = asList(res[1]);
      _ok
        ..clear()
        ..addAll({for (final c in checks) toNum(c['item_id']).toInt(): c['ok'] == true});
      final rep = res[2] == null ? null : asMap(res[2]);
      _reportId = rep?['id'] as String?;
      _catatan.text = '${rep?['catatan'] ?? ''}';
      _fotoLama = _reportId == null
          ? []
          : asList(await db
              .from('photos')
              .select('path,sumber,flags')
              .eq('ref_tabel', 'display_reports')
              .eq('ref_id', _reportId!)
              .order('created_at'));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_fotoLama.isEmpty && _fotoBaru.isEmpty) {
      showMsg(context, 'Ambil minimal 1 foto area display OPPO');
      return;
    }
    setState(() => _saving = true);
    try {
      final db = Session.db;
      final me = Session.current!;
      final rep = await db
          .from('display_reports')
          .upsert({
            'store_id': t.storeId,
            'tanggal': t.tgl,
            'pc_id': t.pcId,
            'catatan': _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
            'diinput_oleh': me.id,
          }, onConflict: 'store_id,tanggal')
          .select('id')
          .single();
      final id = rep['id'] as String;
      await db.from('display_checks').upsert([
        for (final i in _items)
          {
            'store_id': t.storeId,
            'tanggal': t.tgl,
            'pc_id': t.pcId,
            'item_id': i['id'],
            'ok': _ok[toNum(i['id']).toInt()] ?? false,
          }
      ], onConflict: 'store_id,tanggal,item_id');
      if (_fotoBaru.isNotEmpty) {
        await PhotoService.saveAll(
          storeId: t.storeId,
          pcId: t.pcId,
          refTabel: 'display_reports',
          refId: id,
          photos: _fotoBaru,
        );
      }
      if (!mounted) return;
      showMsg(context, 'Cek display tersimpan');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final lengkap = _items.every((i) => _ok[toNum(i['id']).toInt()] == true);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cek display'),
          Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      bottomNavigationBar: _loading || _error != null || !boleh
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: busyIcon(_saving, Icons.save),
                  label: const Text('Simpan cek display'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                  if (_reportId != null) const InfoBanner('Sudah diisi. Bisa ditambah foto atau dikoreksi.', icon: Icons.check_circle),
                  const SectionHeader('Checklist display'),
                  Card(
                    child: Column(children: [
                      for (final i in _items)
                        SwitchListTile(
                          value: _ok[toNum(i['id']).toInt()] ?? false,
                          onChanged: boleh ? (v) => setState(() => _ok[toNum(i['id']).toInt()] = v) : null,
                          title: Text('${i['nama']}'),
                          subtitle: i['keterangan'] == null ? null : Text('${i['keterangan']}'),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(lengkap ? 'Display lengkap' : 'Display belum lengkap',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: lengkap ? Colors.green.shade700 : Colors.orange.shade800)),
                  ),
                  const SectionHeader('Foto area display OPPO'),
                  if (_fotoLama.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library),
                      title: Text('${_fotoLama.length} foto sudah tersimpan'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PhotoViewerPage(photos: _fotoLama, title: 'Display ${t.toko}'))),
                    ),
                  if (boleh)
                    PhotoPickerField(
                      photos: _fotoBaru,
                      onChanged: (p) => setState(() => _fotoBaru = p),
                      label: _fotoLama.isEmpty ? 'Ambil 1-3 foto (wajib)' : 'Tambah foto (opsional)',
                      photoLabel: 'Display OPPO',
                      max: 3,
                      toko: t.toko,
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _catatan,
                    enabled: boleh,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Catatan (opsional)', hintText: 'Misal: dummy A7 Pro belum datang'),
                  ),
                ]),
    );
  }
}
