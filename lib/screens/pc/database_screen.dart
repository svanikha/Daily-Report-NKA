import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../data/targets.dart';
import '../../services/pc_sync.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import 'contact_detail.dart';
import 'contact_form.dart';

class DatabaseScreen extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  const DatabaseScreen({super.key, required this.pc, this.adminView = false});

  @override
  State<DatabaseScreen> createState() => DatabaseScreenState();
}

class DatabaseScreenState extends State<DatabaseScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _contacts = [];
  final Map<String, int> _monthCount = {};
  Map<String, dynamic> _rToday = {};
  Map<String, dynamic> _rMonth = {};
  Map<String, num> _targets = {};
  int _mode = 0; // 0 semua, 1 follow up hari ini, 2 terlewat
  String? _kat;
  String? _status;
  String _q = '';

  void showToday() => setState(() => _mode = 1);

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
      final pcId = widget.pc.id;
      final t = todayStr();
      final ms = ymd(monthStart());
      final res = await Future.wait<dynamic>([
        db.from('contacts').select().eq('pc_id', pcId).order('created_at', ascending: false),
        db.from('contact_logs').select('contact_id').eq('pc_id', pcId).eq('dihubungi', true).gte('waktu', monthStartUtcIso()),
        db.rpc('rekap_pc', params: {'p_pc': pcId, 'p_dari': t, 'p_sampai': t}),
        db.rpc('rekap_pc', params: {'p_pc': pcId, 'p_dari': ms, 'p_sampai': t}),
        loadTargets(pcId, monthStart()),
      ]);
      _contacts = asList(res[0]);
      _monthCount.clear();
      for (final l in asList(res[1])) {
        final id = l['contact_id'] as String;
        _monthCount[id] = (_monthCount[id] ?? 0) + 1;
      }
      _rToday = asMap(res[2]);
      _rMonth = asMap(res[3]);
      _targets = res[4] as Map<String, num>;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _filtered(DateTime today) {
    final q = _q.toLowerCase();
    return _contacts.where((c) {
      if (_kat != null && c['kategori'] != _kat) return false;
      if (_status != null && c['status'] != _status) return false;
      if (q.isNotEmpty) {
        final hit = '${c['nama']}'.toLowerCase().contains(q) || '${c['no_hp']}'.contains(q);
        if (!hit) return false;
      }
      if (_mode == 1 && !isDueToday(c, today)) return false;
      if (_mode == 2 && !isOverdue(c, today)) return false;
      return true;
    }).toList();
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ContactDetail(pc: widget.pc, contactId: id, adminView: widget.adminView),
    ));
    _load();
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ContactForm(pc: widget.pc),
    ));
    if (ok == true) {
      _load();
      PcSync.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = wibToday();
    final dueToday = _contacts.where((c) => isDueToday(c, today)).length;
    final overdue = _contacts.where((c) => isOverdue(c, today)).length;
    final list = _filtered(today);
    final targetDb = _targets['database_baru'] ?? 0;
    final dbMonth = toNum(_rMonth['db_baru']);
    return Scaffold(
      appBar: pcAppBar(context, 'Database', widget.pc, widget.adminView, onRefresh: _load),
      floatingActionButton: widget.adminView
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Database baru'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                    StatGrid(children: [
                      StatCard(
                        icon: Icons.chat,
                        label: 'User dihubungi hari ini',
                        value: angka(toNum(_rToday['dihubungi_unik'])),
                        sub: '${angka(toNum(_rToday['total_kontak']))} kali kontak',
                      ),
                      StatCard(
                        icon: Icons.forum,
                        label: 'User dihubungi bulan ini',
                        value: angka(toNum(_rMonth['dihubungi_unik'])),
                        sub: '${angka(toNum(_rMonth['total_kontak']))} kali kontak',
                      ),
                      StatCard(
                        icon: Icons.person_add,
                        label: 'Database baru hari ini',
                        value: angka(toNum(_rToday['db_baru'])),
                      ),
                      StatCard(
                        icon: Icons.groups,
                        label: 'Database baru bulan ini',
                        value: angka(dbMonth),
                        sub: targetDb > 0 ? 'Target ${angka(targetDb)} · ${pctStr(dbMonth, targetDb)}' : 'Target belum diatur',
                        color: targetDb > 0 ? pctColor(pct(dbMonth, targetDb)) : null,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(value: 0, label: Text('Semua')),
                        ButtonSegment(value: 1, label: Text('Hari ini ($dueToday)')),
                        ButtonSegment(value: 2, label: Text('Terlewat ($overdue)')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Cari nama atau nomor',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _q = v.trim()),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final k in kategoriUser)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(k),
                              selected: _kat == k,
                              onSelected: (v) => setState(() => _kat = v ? k : null),
                            ),
                          ),
                        const SizedBox(width: 8),
                        for (final s in statusUser)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(s),
                              selected: _status == s,
                              onSelected: (v) => setState(() => _status = v ? s : null),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text('${list.length} kontak', style: Theme.of(context).textTheme.labelMedium),
                    if (list.isEmpty) const EmptyState(icon: Icons.contacts, text: 'Belum ada kontak di filter ini'),
                    for (final c in list) _tile(c, today),
                  ]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> c, DateTime today) {
    final terlewat = isOverdue(c, today);
    final hariIni = isDueToday(c, today);
    final n = _monthCount[c['id']] ?? 0;
    final lastRaw = c['last_contacted_at'];
    final last = lastRaw == null ? 'belum pernah' : tgl(parseWib(lastRaw as String));
    return Card(
      child: ListTile(
        onTap: () => _open(c['id'] as String),
        title: Text('${c['nama']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${c['no_hp']} · ${c['kategori']}\nDihubungi bulan ini: $n · Terakhir: $last'),
        isThreeLine: true,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip('${c['status']}'),
            if (terlewat)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Terlewat', style: TextStyle(color: Colors.red, fontSize: 11)),
              )
            else if (hariIni)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Follow up hari ini', style: TextStyle(color: Colors.deepOrange, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
