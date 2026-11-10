import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/targets.dart';
import '../../services/pc_sync.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';
import 'checklist_tab.dart';
import 'leasing_form.dart';
import 'social_form.dart';

class ActivityScreen extends StatelessWidget {
  final Profile pc;
  final bool adminView;
  const ActivityScreen({super.key, required this.pc, this.adminView = false});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: pcAppBar(
          context,
          'Activity',
          pc,
          adminView,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Sosmed'), Tab(text: 'Leasing'), Tab(text: 'Checklist')],
          ),
        ),
        body: TabBarView(children: [
          SosmedTab(pc: pc, adminView: adminView),
          LeasingTab(pc: pc, adminView: adminView),
          ChecklistTab(pc: pc, adminView: adminView),
        ]),
      ),
    );
  }
}

/// Mengambil foto (path, sumber) per ref_id.
Future<Map<String, List<Map<String, dynamic>>>> loadPhotos(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = await Session.db.from('photos').select('ref_id,path,sumber,flags').inFilter('ref_id', ids).order('created_at');
  final map = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    map.putIfAbsent(r['ref_id'] as String, () => []).add(r);
  }
  return map;
}

Future<void> _markNihil(BuildContext context, String pcId) async {
  final ok = await confirmDialog(context, 'Laporkan nihil?', 'Tandai bahwa hari ini tidak ada aktivitas sosmed maupun cek limit.');
  if (!ok) return;
  await Session.db.from('checkins').upsert(
    {'pc_id': pcId, 'tanggal': todayStr(), 'modul': 'activity'},
    onConflict: 'pc_id,tanggal,modul',
  );
  PcSync.refresh();
}

// ---------------------------------------------------------------------
// SOSMED
// ---------------------------------------------------------------------
class SosmedTab extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  const SosmedTab({super.key, required this.pc, this.adminView = false});

  @override
  State<SosmedTab> createState() => _SosmedTabState();
}

class _SosmedTabState extends State<SosmedTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _photos = {};
  Map<String, num> _targets = {};
  bool _nihilToday = false;

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
        db
            .from('social_activities')
            .select()
            .eq('pc_id', widget.pc.id)
            .gte('tanggal', ymd(monthStart()))
            .lte('tanggal', ymd(monthEnd()))
            .order('tanggal', ascending: false)
            .order('created_at', ascending: false),
        loadTargets(widget.pc.id, monthStart()),
        db.from('checkins').select('modul').eq('pc_id', widget.pc.id).eq('tanggal', todayStr()).eq('modul', 'activity'),
      ]);
      _rows = asList(res[0]);
      _targets = res[1] as Map<String, num>;
      _nihilToday = asList(res[2]).isNotEmpty;
      _photos = await loadPhotos(_rows.map((r) => r['id'] as String).toList());
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SocialForm(pc: widget.pc)));
    if (ok == true) {
      _load();
      PcSync.refresh();
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Hapus aktivitas?', 'Data dan foto bukti akan dihapus.', yes: 'Hapus');
    if (!ok) return;
    try {
      final db = Session.db;
      final photos = _photos[r['id']] ?? [];
      if (photos.isNotEmpty) {
        await db.storage.from('bukti').remove(photos.map((p) => p['path'] as String).toList());
        await db.from('photos').delete().eq('ref_id', r['id'] as String);
      }
      await db.from('social_activities').delete().eq('id', r['id'] as String);
      _load();
      PcSync.refresh();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final today = todayStr();
    final canAdd = !widget.adminView && pcInputOpen();
    return Scaffold(
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add_sosmed',
              onPressed: _add,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Report sosmed'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                    if (!widget.adminView && !pcInputOpen())
                      const InfoBanner('Input hari ini sudah ditutup (batas pukul 23.00 WIB).', icon: Icons.lock_clock, color: Colors.red),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          for (final d in sosmedDefs)
                            ProgressTile(
                              label: d.label,
                              actual: _rows.where((r) => r['kode'] == d.kode).fold<num>(0, (a, r) => a + toNum(r['jumlah'])),
                              target: _targets[d.kode] ?? 0,
                              fmt: (v) => '${angka(v)} ${d.satuan}',
                              extra: 'hari ini ${angka(_rows.where((r) => r['kode'] == d.kode && r['tanggal'] == today).fold<num>(0, (a, r) => a + toNum(r['jumlah'])))}',
                            ),
                        ]),
                      ),
                    ),
                    if (!widget.adminView && pcInputOpen() && !_nihilToday && !_rows.any((r) => r['tanggal'] == today))
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await _markNihil(context, widget.pc.id);
                            _load();
                          } catch (e) {
                            if (context.mounted) showErr(context, e);
                          }
                        },
                        icon: const Icon(Icons.do_not_disturb_on_outlined),
                        label: const Text('Laporkan nihil aktivitas hari ini'),
                      ),
                    const SectionHeader('Riwayat bulan ini'),
                    if (_rows.isEmpty) const EmptyState(icon: Icons.campaign, text: 'Belum ada aktivitas sosmed bulan ini'),
                    for (final r in _rows) _tile(r),
                  ]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final def = sosmedByKode(r['kode'] as String?);
    final photos = _photos[r['id']] ?? [];
    final link = (r['link'] ?? '').toString();
    return Card(
      child: ListTile(
        onTap: photos.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PhotoViewerPage(photos: photos, title: def?.label ?? 'Bukti'),
                )),
        leading: const Icon(Icons.photo_library),
        title: Text('${def?.label ?? r['kode']} · ${r['jumlah']} ${def?.satuan ?? ''}'),
        subtitle: Text('${tglPendek(parseDate('${r['tanggal']}'))} · ${photos.length} foto${link.isNotEmpty ? '\n$link' : ''}'),
        trailing: (adminCanEdit(widget.adminView) || canPcEdit('${r['tanggal']}'))
            ? IconButton(onPressed: () => _delete(r), icon: const Icon(Icons.delete_outline))
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// LEASING
// ---------------------------------------------------------------------
class LeasingTab extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  const LeasingTab({super.key, required this.pc, this.adminView = false});

  @override
  State<LeasingTab> createState() => _LeasingTabState();
}

class _LeasingTabState extends State<LeasingTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, List<Map<String, dynamic>>> _photos = {};
  Map<String, num> _targets = {};

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
      final res = await Future.wait<dynamic>([
        Session.db
            .from('leasing_checks')
            .select('*, contacts(nama)')
            .eq('pc_id', widget.pc.id)
            .gte('tanggal', ymd(monthStart()))
            .lte('tanggal', ymd(monthEnd()))
            .order('tanggal', ascending: false)
            .order('created_at', ascending: false),
        loadTargets(widget.pc.id, monthStart()),
      ]);
      _rows = asList(res[0]);
      _targets = res[1] as Map<String, num>;
      _photos = await loadPhotos(_rows.map((r) => r['id'] as String).toList());
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LeasingForm(pc: widget.pc)));
    if (ok == true) {
      _load();
      PcSync.refresh();
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context, 'Hapus cek limit?', 'Data dan foto selfie akan dihapus.', yes: 'Hapus');
    if (!ok) return;
    try {
      final db = Session.db;
      final photos = _photos[r['id']] ?? [];
      if (photos.isNotEmpty) {
        await db.storage.from('bukti').remove(photos.map((p) => p['path'] as String).toList());
        await db.from('photos').delete().eq('ref_id', r['id'] as String);
      }
      await db.from('leasing_checks').delete().eq('id', r['id'] as String);
      _load();
      PcSync.refresh();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final today = todayStr();
    final canAdd = !widget.adminView && pcInputOpen();
    final totalCek = _rows.length;
    final totalApprove = _rows.where((r) => r['hasil'] == 'Approve').length;
    return Scaffold(
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add_leasing',
              onPressed: _add,
              icon: const Icon(Icons.camera_front),
              label: const Text('Cek limit'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                    if (!widget.adminView && !pcInputOpen())
                      const InfoBanner('Input hari ini sudah ditutup (batas pukul 23.00 WIB).', icon: Icons.lock_clock, color: Colors.red),
                    StatGrid(children: [
                      StatCard(
                        icon: Icons.fact_check,
                        label: 'Cek limit hari ini',
                        value: angka(_rows.where((r) => r['tanggal'] == today).length),
                      ),
                      StatCard(
                        icon: Icons.verified,
                        label: 'Cek limit bulan ini',
                        value: angka(totalCek),
                        sub: 'Approve $totalApprove · Reject ${totalCek - totalApprove}',
                      ),
                    ]),
                    const SectionHeader('Rekap per leasing (bulan ini)'),
                    for (final l in leasingList) _leasingCard(l, today),
                    const SectionHeader('Riwayat bulan ini'),
                    if (_rows.isEmpty) const EmptyState(icon: Icons.fact_check, text: 'Belum ada cek limit bulan ini'),
                    for (final r in _rows) _tile(r),
                  ]),
                ),
    );
  }

  Widget _leasingCard(String l, String today) {
    final rows = _rows.where((r) => r['leasing'] == l).toList();
    final approve = rows.where((r) => r['hasil'] == 'Approve').toList();
    final reject = rows.length - approve.length;
    final avgLimit = approve.isEmpty ? 0 : approve.fold<num>(0, (a, r) => a + toNum(r['limit_disetujui'])) / approve.length;
    final rejectRate = rows.isEmpty ? 0 : reject / rows.length * 100;
    final target = _targets['leasing_$l'] ?? 0;
    final todayCount = rows.where((r) => r['tanggal'] == today).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProgressTile(
            label: l,
            actual: rows.length,
            target: target,
            fmt: (v) => '${angka(v)} cek',
            extra: 'hari ini $todayCount',
          ),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Pill('Approve ${approve.length}', color: Colors.green.shade700),
            Pill('Reject $reject', color: Colors.red.shade700),
            Pill('Rata-rata limit ${rupiah(avgLimit.round())}', color: Colors.indigo),
            Pill('Reject rate ${rejectRate.toStringAsFixed(0)}%', color: Colors.orange.shade800),
          ]),
        ]),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final photos = _photos[r['id']] ?? [];
    final approve = r['hasil'] == 'Approve';
    final konsumen = r['contacts'] is Map ? (r['contacts'] as Map)['nama'] : null;
    return Card(
      child: ListTile(
        onTap: photos.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PhotoViewerPage(photos: photos, title: 'Selfie ${r['leasing']}'),
                )),
        leading: Icon(approve ? Icons.check_circle : Icons.cancel, color: approve ? Colors.green : Colors.red),
        title: Text('${r['leasing']} · ${r['hasil']}${approve ? ' · ${rupiah(toNum(r['limit_disetujui']))}' : ''}'),
        subtitle: Text([
          tglPendek(parseDate('${r['tanggal']}')),
          if (konsumen != null) 'Konsumen: $konsumen',
          '${photos.length} foto',
        ].join(' · ')),
        trailing: (adminCanEdit(widget.adminView) || canPcEdit('${r['tanggal']}'))
            ? IconButton(onPressed: () => _delete(r), icon: const Icon(Icons.delete_outline))
            : null,
      ),
    );
  }
}
