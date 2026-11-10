import 'package:flutter/material.dart';

import '../../services/pc_sync.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';
import 'activity_screen.dart' show loadPhotos;

/// Checklist Standar Toko: 1 foto kamera per item, setiap hari kerja.
/// Saat dibuka admin, juga menampilkan riwayat istirahat PC bulan ini.
class ChecklistTab extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  const ChecklistTab({super.key, required this.pc, this.adminView = false});

  @override
  State<ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<ChecklistTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _month = [];
  Map<String, List<Map<String, dynamic>>> _photos = {};
  String? _libur;
  List<Map<String, dynamic>> _breaks = [];
  int? _busyItem;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('checklist_items').select().eq('aktif', true).order('urutan').order('id'),
        db
            .from('store_checklists')
            .select('id,tanggal,item_id')
            .eq('pc_id', widget.pc.id)
            .gte('tanggal', ymd(monthStart()))
            .lte('tanggal', ymd(monthEnd())),
        db.from('pc_day_status').select('status').eq('pc_id', widget.pc.id).eq('tanggal', todayStr()),
        if (widget.adminView)
          db
              .from('breaks')
              .select()
              .eq('pc_id', widget.pc.id)
              .gte('tanggal', ymd(monthStart()))
              .order('tanggal', ascending: false),
      ]);
      _items = asList(res[0]);
      _month = asList(res[1]);
      final l = asList(res[2]);
      _libur = l.isEmpty ? null : '${l.first['status']}';
      _breaks = widget.adminView ? asList(res[3]) : [];
      final todayIds = _month.where((r) => r['tanggal'] == todayStr()).map((r) => r['id'] as String).toList();
      _photos = await loadPhotos(todayIds);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? _doneToday(int itemId) {
    for (final r in _month) {
      if (r['tanggal'] == todayStr() && toNum(r['item_id']).toInt() == itemId) return r;
    }
    return null;
  }

  Future<void> _take(Map<String, dynamic> item) async {
    final itemId = toNum(item['id']).toInt();
    PickedPhoto? photo;
    try {
      photo = await PhotoService.pick(context, label: '${item['nama']}', kind: PhotoKind.foto, cameraOnly: true);
    } on PhotoRejected catch (e) {
      if (mounted) await showRejected(context, e.message);
      return;
    } catch (e) {
      if (mounted) showErr(context, e);
      return;
    }
    if (photo == null) return;
    if (!pcInputOpen()) {
      if (mounted) showMsg(context, 'Input hari ini sudah ditutup (batas pukul 23.00 WIB)');
      return;
    }
    setState(() => _busyItem = itemId);
    String? rowId;
    try {
      final row = await Session.db
          .from('store_checklists')
          .insert({
            'pc_id': widget.pc.id,
            'store_id': widget.pc.storeId,
            'tanggal': todayStr(),
            'item_id': itemId,
          })
          .select()
          .single();
      rowId = row['id'] as String;
      await PhotoService.saveAll(pcId: widget.pc.id, refTabel: 'store_checklists', refId: rowId, photos: [photo]);
      PcSync.refresh();
      if (mounted && photo.flags.isNotEmpty) {
        showMsg(context, 'Tersimpan dengan tanda: ${photo.flags.map((f) => flagLabel[f] ?? f).join(', ')}');
      }
    } catch (e) {
      // Foto gagal diupload: batalkan baris checklist agar tidak tercatat Sudah tanpa foto.
      if (rowId != null) {
        try {
          await Session.db.from('store_checklists').delete().eq('id', rowId);
        } catch (_) {}
      }
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busyItem = null);
    _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await confirmDialog(context, 'Hapus checklist?', 'Foto bukti item ini akan dihapus.', yes: 'Hapus');
    if (!ok) return;
    try {
      final db = Session.db;
      final photos = _photos[row['id']] ?? [];
      if (photos.isNotEmpty) {
        await db.storage.from('bukti').remove(photos.map((p) => p['path'] as String).toList());
        await db.from('photos').delete().eq('ref_id', row['id'] as String);
      }
      await db.from('store_checklists').delete().eq('id', row['id'] as String);
      PcSync.refresh();
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);

    final ids = _items.map((i) => toNum(i['id']).toInt()).toSet();
    final doneToday = _items.where((i) => _doneToday(toNum(i['id']).toInt()) != null).length;
    final perDay = <String, Set<int>>{};
    for (final r in _month) {
      final id = toNum(r['item_id']).toInt();
      if (ids.contains(id)) perDay.putIfAbsent('${r['tanggal']}', () => <int>{}).add(id);
    }
    final hariLengkap = ids.isEmpty ? 0 : perDay.values.where((s) => s.length >= ids.length).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        if (!widget.adminView && !pcInputOpen())
          const InfoBanner('Input hari ini sudah ditutup (batas pukul 23.00 WIB).', icon: Icons.lock_clock, color: Colors.red),
        if (_libur != null)
          InfoBanner('Hari ini ${_libur == 'izin' ? 'izin' : 'offday'}: checklist tidak wajib.', icon: Icons.beach_access, color: Colors.teal),
        StatGrid(children: [
          StatCard(
            icon: Icons.checklist,
            label: 'Checklist hari ini',
            value: '$doneToday/${_items.length}',
            color: doneToday >= _items.length && _items.isNotEmpty ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          StatCard(icon: Icons.event_available, label: 'Hari lengkap bulan ini', value: '$hariLengkap hari'),
        ]),
        const SectionHeader('Checklist Standar Toko'),
        Text('Ambil 1 foto langsung dari kamera untuk setiap item. Foto galeri tidak diterima.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (_items.isEmpty) const EmptyState(icon: Icons.checklist, text: 'Belum ada item checklist dari RBM'),
        for (final item in _items) _itemCard(item),
        if (widget.adminView) ...[
          const SectionHeader('Riwayat istirahat bulan ini'),
          if (_breaks.isEmpty) const EmptyState(icon: Icons.free_breakfast, text: 'Belum ada catatan istirahat'),
          for (final b in _breaks) _breakTile(b),
        ],
      ]),
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final id = toNum(item['id']).toInt();
    final row = _doneToday(id);
    final photos = row == null ? <Map<String, dynamic>>[] : (_photos[row['id']] ?? []);
    final flags = photos.expand((p) => (p['flags'] is List ? p['flags'] as List : const [])).toSet().toList();
    final busy = _busyItem == id;
    return Card(
      child: ListTile(
        leading: Icon(row != null ? Icons.check_circle : Icons.radio_button_unchecked,
            color: row != null ? Colors.green.shade700 : Colors.grey),
        title: Text('${item['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((item['keterangan'] ?? '').toString().isNotEmpty) Text('${item['keterangan']}'),
          if (flags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, children: photoFlagPills(flags))),
        ]),
        onTap: photos.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PhotoViewerPage(photos: photos, title: '${item['nama']}'),
                )),
        trailing: row != null
            ? ((adminCanEdit(widget.adminView) || canPcEdit(todayStr()))
                ? IconButton(onPressed: () => _delete(row), icon: const Icon(Icons.delete_outline))
                : const Text('Sudah'))
            : (widget.adminView || !pcInputOpen())
                ? const Text('Belum', style: TextStyle(color: Colors.red))
                : FilledButton.tonalIcon(
                    onPressed: busy ? null : () => _take(item),
                    icon: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_camera, size: 18),
                    label: const Text('Foto'),
                  ),
      ),
    );
  }

  Widget _breakTile(Map<String, dynamic> b) {
    final mulai = parseWib(b['mulai'] as String);
    final selesai = b['selesai'] == null ? null : parseWib(b['selesai'] as String);
    final menit = (selesai ?? wibNow()).difference(mulai).inMinutes;
    final durasi = toNum(b['durasi_menit'] ?? 180).toInt();
    final label = durasi == 60 ? '1 jam' : '3 jam';
    String jam(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(Icons.free_breakfast, color: menit > durasi ? Colors.red : Colors.blueGrey),
        title: Text(tglPendek(parseDate('${b['tanggal']}'))),
        subtitle: Text('${jam(mulai)} - ${selesai == null ? 'belum kembali' : jam(selesai)} · $menit menit dari $label'
            '${b['jarak_kembali_m'] != null ? ' · kembali ${b['jarak_kembali_m']} m dari toko' : ''}'),
        trailing: Wrap(spacing: 4, children: [
          if (menit > durasi) Pill('> $label', color: Colors.red.shade700),
          if (b['flag'] == 'tidak_klik_kembali') Pill('Tidak klik kembali', color: Colors.red.shade700),
        ]),
      ),
    );
  }
}
