import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';

/// Cek display harian: PC WAJIB mengirim foto untuk SETIAP kategori checklist
/// (POSM, dummy, harga, dst.). Tidak ada saklar nyala/mati: kategori dianggap selesai
/// jika sudah ada fotonya. TL / Trainer / PIC bisa menghapus isian satu kategori jika salah,
/// lalu PC mendapat pengingat untuk mengirim ulang.
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
  String? _reportId;

  /// itemId -> id baris display_checks (jika sudah dikirim)
  final Map<int, String> _checkId = {};

  /// itemId -> foto yang sudah tersimpan
  final Map<int, List<Map<String, dynamic>>> _fotoLama = {};

  /// itemId -> foto baru yang belum dikirim
  final Map<int, List<PickedPhoto>> _fotoBaru = {};

  /// Foto display versi lama (sebelum foto per kategori), hanya untuk dilihat.
  List<Map<String, dynamic>> _fotoUmum = [];
  final _catatan = TextEditingController();

  TokoHari get t => widget.toko;
  Profile get me => Session.current!;
  bool get _atasan => me.isTl || me.isTrainer || me.isPic;

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
        db.from('display_checks').select('id,item_id').eq('store_id', t.storeId).eq('tanggal', t.tgl),
        db.from('display_reports').select('id,catatan').eq('store_id', t.storeId).eq('tanggal', t.tgl).maybeSingle(),
      ]);
      _items = asList(res[0]);
      _checkId
        ..clear()
        ..addAll({for (final c in asList(res[1])) toNum(c['item_id']).toInt(): '${c['id']}'});
      final rep = res[2] == null ? null : asMap(res[2]);
      _reportId = rep?['id'] as String?;
      _catatan.text = '${rep?['catatan'] ?? ''}';

      _fotoLama.clear();
      final ids = _checkId.values.toList();
      if (ids.isNotEmpty) {
        final fotos = asList(await db
            .from('photos')
            .select('ref_id,path,sumber,flags')
            .eq('ref_tabel', 'display_checks')
            .inFilter('ref_id', ids)
            .order('created_at'));
        final byCheck = {for (final e in _checkId.entries) e.value: e.key};
        for (final f in fotos) {
          final item = byCheck['${f['ref_id']}'];
          if (item != null) _fotoLama.putIfAbsent(item, () => []).add(f);
        }
      }
      _fotoUmum = _reportId == null
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

  int _id(Map<String, dynamic> i) => toNum(i['id']).toInt();
  bool _sudah(int item) => (_fotoLama[item]?.isNotEmpty ?? false);
  bool _siap(int item) => _sudah(item) || (_fotoBaru[item]?.isNotEmpty ?? false);

  Future<void> _save() async {
    final kurang = [for (final i in _items) if (!_siap(_id(i))) '${i['nama']}'];
    if (kurang.isNotEmpty) {
      showMsg(context, 'Foto wajib untuk setiap kategori. Belum ada foto: ${kurang.join(', ')}');
      return;
    }
    setState(() => _saving = true);
    try {
      final db = Session.db;
      // 1. Setiap kategori yang punya foto baru: catat checklist (selesai) lalu unggah fotonya
      for (final i in _items) {
        final item = _id(i);
        final baru = _fotoBaru[item] ?? const <PickedPhoto>[];
        if (baru.isEmpty) continue;
        final row = await db
            .from('display_checks')
            .upsert({'store_id': t.storeId, 'tanggal': t.tgl, 'pc_id': t.pcId, 'item_id': item, 'ok': true},
                onConflict: 'store_id,tanggal,item_id')
            .select('id')
            .single();
        await PhotoService.saveAll(
          storeId: t.storeId,
          pcId: t.pcId,
          refTabel: 'display_checks',
          refId: '${row['id']}',
          photos: baru,
        );
        _fotoBaru.remove(item);
      }
      // 2. Laporan display hari ini (memicu notifikasi ke atasan)
      await db.from('display_reports').upsert({
        'store_id': t.storeId,
        'tanggal': t.tgl,
        'pc_id': t.pcId,
        'catatan': _catatan.text.trim().isEmpty ? null : _catatan.text.trim(),
        'diinput_oleh': me.id,
      }, onConflict: 'store_id,tanggal');
      if (!mounted) return;
      showMsg(context, 'Cek display terkirim');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showErr(context, e);
        _load();
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _hapus(Map<String, dynamic> i) async {
    final ok = await confirmDialog(
      context,
      'Hapus display "${i['nama']}"?',
      'Foto kategori ini dihapus dan PC harus mengirim ulang. PC mendapat pengingat otomatis.',
      yes: 'Hapus',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await Session.db.rpc('hapus_display_item', params: {'p_store': t.storeId, 'p_tanggal': t.tgl, 'p_item': _id(i)});
      await _load();
      if (mounted) showMsg(context, 'Display "${i['nama']}" dihapus');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final selesai = _items.where((i) => _sudah(_id(i))).length;
    final adaBaru = _fotoBaru.values.any((l) => l.isNotEmpty);
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
                  onPressed: _saving || (!adaBaru && _reportId != null && selesai == _items.length) ? null : _save,
                  icon: busyIcon(_saving, Icons.send),
                  label: Text(adaBaru || _reportId == null ? 'Kirim cek display' : 'Semua kategori sudah terkirim'),
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
                  InfoBanner(
                    'Wajib kirim foto untuk SETIAP kategori di bawah. '
                    '${_atasan ? 'Ketuk ikon tempat sampah untuk menghapus kategori yang salah; PC akan mengirim ulang.' : 'Kategori yang dihapus atasan harus difoto ulang.'}',
                    icon: Icons.photo_camera,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      selesai == _items.length && _items.isNotEmpty
                          ? 'Display lengkap ($selesai/${_items.length} kategori)'
                          : 'Terkirim $selesai/${_items.length} kategori',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selesai == _items.length ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                    ),
                  ),
                  for (final i in _items) _kategori(i, boleh),
                  if (_fotoUmum.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library),
                      title: Text('${_fotoUmum.length} foto display umum (versi lama)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PhotoViewerPage(photos: _fotoUmum, title: 'Display ${t.toko}'))),
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

  Widget _kategori(Map<String, dynamic> i, bool boleh) {
    final id = _id(i);
    final lama = _fotoLama[id] ?? const <Map<String, dynamic>>[];
    final baru = _fotoBaru[id] ?? const <PickedPhoto>[];
    final sudah = lama.isNotEmpty;
    final c = sudah ? Colors.green.shade700 : (baru.isNotEmpty ? Colors.blue.shade700 : Colors.grey.shade600);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(sudah ? Icons.check_circle : Icons.radio_button_unchecked, color: c),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i['nama']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (i['keterangan'] != null) Text('${i['keterangan']}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (_atasan && (_checkId.containsKey(id) || sudah))
              IconButton(
                tooltip: 'Hapus kategori ini (salah)',
                onPressed: _saving ? null : () => _hapus(i),
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
              ),
          ]),
          const SizedBox(height: 4),
          if (sudah)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library),
              title: Text('${lama.length} foto terkirim'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PhotoViewerPage(photos: lama, title: '${i['nama']} · ${t.toko}'))),
            ),
          if (boleh)
            PhotoPickerField(
              photos: baru,
              onChanged: (p) => setState(() => _fotoBaru[id] = p),
              label: sudah ? 'Tambah foto (opsional)' : 'Foto ${i['nama']} (wajib)',
              photoLabel: '${i['nama']}',
              max: 3,
              toko: t.toko,
            )
          else if (!sudah)
            Text('Belum ada foto', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
