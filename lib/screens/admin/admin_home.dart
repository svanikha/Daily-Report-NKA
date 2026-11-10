import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../data/catalog.dart';
import '../../services/push_service.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/nosell_calendar.dart';
import '../../widgets/widgets.dart';
import '../pc/pc_home.dart';
import 'admin_gallery.dart';
import 'admin_inbox.dart';
import 'admin_manage.dart';
import 'sm_report_screen.dart';

/// Dashboard admin: rekap semua PC per modul + menu kelola.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  String _preset = 'hari';
  DateTime _dari = wibToday();
  DateTime _sampai = wibToday();
  int? _storeId;
  String? _pcId;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _sales = [];
  // Data bulan berjalan untuk heatmap NOSELL
  List<Map<String, dynamic>> _mSales = [];
  List<Map<String, dynamic>> _mNihil = [];
  List<Map<String, dynamic>> _mLibur = [];

  int _unread = 0;
  RealtimeChannel? _inboxChannel;

  @override
  void initState() {
    super.initState();
    if (_isSupport) _storeId = Session.current?.storeId;
    PushService.onOpenInbox = () {
      if (mounted) _openInbox();
    };
    PushService.registerAdmin();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
    _load();
    _loadUnread();
    _inboxChannel = Session.db
        .channel('admin_inbox_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_events',
          callback: (_) {
            if (mounted) setState(() => _unread++);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    PushService.onOpenInbox = null;
    final c = _inboxChannel;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
  }

  /// Admin support: hanya melihat tokonya sendiri dan tidak bisa mengubah data.
  bool get _isSupport => Session.current?.isSupport ?? false;

  Future<void> _loadUnread() async {
    try {
      final res = await Session.db.rpc('my_inbox_unread');
      if (mounted) setState(() => _unread = toNum(res).toInt());
    } catch (_) {}
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminInbox()));
    _loadUnread();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Session.db;
      final ms = ymd(monthStart(_sampai));
      final me = ymd(monthEnd(_sampai));
      final res = await Future.wait<dynamic>([
        db.rpc('rekap_semua', params: {'p_dari': ymd(_dari), 'p_sampai': ymd(_sampai)}),
        db.from('stores').select().order('nama'),
        db
            .from('sales')
            .select('pc_id,tanggal,tipe,nama_produk,qty,subtotal,metode,leasing')
            .gte('tanggal', ymd(_dari))
            .lte('tanggal', ymd(_sampai)),
        db.from('sales').select('pc_id,tanggal,tipe,qty').gte('tanggal', ms).lte('tanggal', me),
        db.from('checkins').select('pc_id,tanggal').eq('modul', 'report').gte('tanggal', ms).lte('tanggal', me),
        db.from('pc_day_status').select('pc_id,tanggal,status').gte('tanggal', ms).lte('tanggal', me),
      ]);
      _all = asList(res[0]);
      _stores = asList(res[1]);
      _sales = asList(res[2]);
      _mSales = asList(res[3]);
      _mNihil = asList(res[4]);
      _mLibur = asList(res[5]);
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setPreset(String p) async {
    final today = wibToday();
    if (p == 'hari') {
      _dari = today;
      _sampai = today;
    } else if (p == 'kemarin') {
      _dari = addDays(today, -1);
      _sampai = addDays(today, -1);
    } else if (p == 'bulan') {
      _dari = monthStart(today);
      _sampai = today;
    } else {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2026, 1, 1),
        lastDate: today,
        initialDateRange: DateTimeRange(start: _dari, end: _sampai),
      );
      if (r == null) return;
      _dari = dateOnly(r.start);
      _sampai = dateOnly(r.end);
    }
    _preset = p;
    _load();
  }

  List<Map<String, dynamic>> get _rows => _all.where((r) {
        if (_storeId != null && toNum(r['store_id']).toInt() != _storeId) return false;
        if (_pcId != null && r['pc_id'] != _pcId) return false;
        return true;
      }).toList();

  Set<String> get _pcIds => _rows.map((r) => r['pc_id'] as String).toSet();

  num _sumP(List<Map<String, dynamic>> rows, String k) => rows.fold<num>(0, (a, r) => a + toNum(asMap(r['periode'])[k]));
  num _sumB(List<Map<String, dynamic>> rows, String k) => rows.fold<num>(0, (a, r) => a + toNum(asMap(r['bulan'])[k]));
  num _sumT(List<Map<String, dynamic>> rows, String k) => rows.fold<num>(0, (a, r) => a + toNum(asMap(r['target'])[k]));
  num _sosmedP(List<Map<String, dynamic>> rows, String kode) =>
      rows.fold<num>(0, (a, r) => a + toNum(asMap(asMap(r['periode'])['sosmed'])[kode]));
  num _sosmedB(List<Map<String, dynamic>> rows, String kode) =>
      rows.fold<num>(0, (a, r) => a + toNum(asMap(asMap(r['bulan'])['sosmed'])[kode]));

  /// Gabungan statistik leasing dari beberapa PC: leasing -> [total, approve, reject, sumLimit]
  Map<String, List<num>> _leasing(List<Map<String, dynamic>> rows, String field) {
    final m = {for (final l in leasingList) l: <num>[0, 0, 0, 0]};
    for (final r in rows) {
      for (final x in asList(asMap(r[field])['leasing'])) {
        final v = m.putIfAbsent('${x['leasing']}', () => <num>[0, 0, 0, 0]);
        v[0] += toNum(x['total']);
        v[1] += toNum(x['approve']);
        v[2] += toNum(x['reject']);
        v[3] += toNum(x['sum_limit']);
      }
    }
    return m;
  }

  Profile _profileOf(Map<String, dynamic> r) => Profile(
        id: r['pc_id'] as String,
        nama: '${r['nama']}',
        role: 'pc',
        storeId: r['store_id'] == null ? null : toNum(r['store_id']).toInt(),
        toko: '${r['toko']}',
        email: '',
      );

  void _openPc(Map<String, dynamic> r, int tab) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PcHome(pc: _profileOf(r), adminView: true, initialTab: tab),
    ));
  }

  String get _periodLabel => isSameDay(_dari, _sampai) ? hariTgl(_dari) : '${tgl(_dari)} - ${tgl(_sampai)}';

  @override
  Widget build(BuildContext context) {
    final titles = ['Ringkasan', 'Database', 'Report', 'Activity', _isSupport ? 'Akun' : 'Kelola'];
    final body = _tab == 4
        ? (_isSupport ? const SupportAccount() : const AdminManage())
        : _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorRetry(error: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 32), children: [
                      _filterBar(),
                      ...switch (_tab) {
                        0 => _overview(),
                        1 => _database(),
                        2 => _report(),
                        _ => _activity(),
                      },
                    ]),
                  );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titles[_tab]),
          Text(
            _isSupport
                ? 'Store Manager · ${Session.current?.nama ?? ''} · ${(Session.current?.toko ?? '').replaceFirst('OPPO Store - ', '')}'
                : 'RBM · ${Session.current?.nama ?? ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ]),
        actions: [
          if (_isSupport)
            IconButton(
              tooltip: 'Daily Report SM',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmReportScreen())),
              icon: const Icon(Icons.summarize_outlined),
            ),
          IconButton(
            tooltip: 'Pesan masuk',
            onPressed: _openInbox,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          if (_tab != 4) IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Ringkasan'),
          const NavigationDestination(icon: Icon(Icons.contacts_outlined), selectedIcon: Icon(Icons.contacts), label: 'Database'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Report'),
          const NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Activity'),
          _isSupport
              ? const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Akun')
              : const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Kelola'),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final pcsInStore = _all.where((r) => _storeId == null || toNum(r['store_id']).toInt() == _storeId).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in const [
              ['hari', 'Hari ini'],
              ['kemarin', 'Kemarin'],
              ['bulan', 'Bulan ini'],
              ['custom', 'Pilih tanggal'],
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(p[1]), selected: _preset == p[0], onSelected: (_) => _setPreset(p[0])),
              ),
          ]),
        ),
        Row(children: [
          Expanded(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: _storeId,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Semua toko')),
                for (final s in _stores)
                  DropdownMenuItem<int?>(
                    value: toNum(s['id']).toInt(),
                    child: Text('${s['nama']}'.replaceFirst('OPPO Store - ', ''), overflow: TextOverflow.ellipsis),
                  ),
              ],
              // Admin support terkunci di tokonya sendiri
              onChanged: _isSupport
                  ? null
                  : (v) => setState(() {
                        _storeId = v;
                        _pcId = null;
                      }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _pcId,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Semua PC')),
                for (final r in pcsInStore)
                  DropdownMenuItem<String?>(value: r['pc_id'] as String, child: Text('${r['nama']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _pcId = v),
            ),
          ),
        ]),
        Text('Periode: $_periodLabel', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
      ]),
    );
  }

  // -------------------------------------------------------------------
  // RINGKASAN
  // -------------------------------------------------------------------
  List<Widget> _overview() {
    final rows = _rows;
    final sosmedTotal = sosmedDefs.fold<num>(0, (a, d) => a + _sosmedP(rows, d.kode));
    final lp = _leasing(rows, 'periode');
    final cek = lp.values.fold<num>(0, (a, v) => a + v[0]);
    final approve = lp.values.fold<num>(0, (a, v) => a + v[1]);
    final lb = _leasing(rows, 'bulan');
    final cekBulan = lb.values.fold<num>(0, (a, v) => a + v[0]);
    final targetLeasing = leasingList.fold<num>(0, (a, l) => a + _sumT(rows, 'leasing_$l'));
    final belum = rows.where((r) {
      if (r['libur_hari_ini'] != null) return false;
      final m = asMap(r['input_hari_ini']);
      return m['report'] != true || m['activity'] != true || m['database'] != true || m['checklist'] == false;
    }).toList();
    final libur = rows.where((r) => r['libur_hari_ini'] != null).toList();
    final istirahat = rows.where((r) => r['istirahat_hari_ini'] != null).toList()
      ..sort((a, b) => _breakMenit(b).compareTo(_breakMenit(a)));
    final ranked = [...rows]..sort((a, b) {
        final pa = pct(toNum(asMap(a['bulan'])['hp_revenue']), toNum(asMap(a['target'])['revenue_hp']));
        final pb = pct(toNum(asMap(b['bulan'])['hp_revenue']), toNum(asMap(b['target'])['revenue_hp']));
        return pb.compareTo(pa);
      });

    return [
      StatGrid(children: [
        StatCard(icon: Icons.phone_android, label: 'Revenue HP', value: rupiah(_sumP(rows, 'hp_revenue')), sub: '${angka(_sumP(rows, 'hp_unit'))} unit'),
        StatCard(icon: Icons.watch, label: 'IoT', value: '${angka(_sumP(rows, 'iot_unit'))} unit', sub: rupiah(_sumP(rows, 'iot_revenue'))),
        StatCard(icon: Icons.person_add, label: 'Database baru', value: angka(_sumP(rows, 'db_baru'))),
        StatCard(
          icon: Icons.forum,
          label: 'User dihubungi',
          value: angka(_sumP(rows, 'dihubungi_unik')),
          sub: '${angka(_sumP(rows, 'total_kontak'))} kali kontak',
        ),
        StatCard(icon: Icons.campaign, label: 'Aktivitas sosmed', value: angka(sosmedTotal)),
        StatCard(icon: Icons.fact_check, label: 'Cek limit leasing', value: angka(cek), sub: 'Approve ${angka(approve)}'),
      ]),
      const SectionHeader('Pencapaian bulan ini vs target'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            ProgressTile(label: 'Revenue HP', actual: _sumB(rows, 'hp_revenue'), target: _sumT(rows, 'revenue_hp'), fmt: rupiah),
            ProgressTile(label: 'IoT', actual: _sumB(rows, 'iot_unit'), target: _sumT(rows, 'iot_unit'), fmt: (v) => '${angka(v)} unit'),
            ProgressTile(label: 'Database baru', actual: _sumB(rows, 'db_baru'), target: _sumT(rows, 'database_baru'), fmt: (v) => angka(v)),
            for (final d in sosmedDefs)
              ProgressTile(label: d.label, actual: _sosmedB(rows, d.kode), target: _sumT(rows, d.kode), fmt: (v) => angka(v)),
            ProgressTile(label: 'Cek limit leasing (semua)', actual: cekBulan, target: targetLeasing, fmt: (v) => angka(v)),
          ]),
        ),
      ),
      SectionHeader('Belum input hari ini (${belum.length} PC)'),
      if (belum.isEmpty)
        const InfoBanner('Semua PC sudah input hari ini.', icon: Icons.check_circle, color: Colors.green)
      else
        Card(
          child: Column(children: [
            for (final r in belum)
              ListTile(
                title: Text('${r['nama']}'),
                subtitle: Text('${r['toko']}'),
                trailing: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final m in const ['database', 'report', 'activity', 'checklist'])
                    if (asMap(r['input_hari_ini'])[m] == false) Pill(m[0].toUpperCase() + m.substring(1), color: Colors.red.shade700),
                ]),
                onTap: () => _openPc(r, 0),
              ),
          ]),
        ),
      if (libur.isNotEmpty) ...[
        SectionHeader('Offday / izin hari ini (${libur.length} PC)'),
        Card(
          child: Column(children: [
            for (final r in libur)
              ListTile(
                dense: true,
                leading: const Icon(Icons.beach_access, color: Colors.teal),
                title: Text('${r['nama']}'),
                subtitle: Text('${r['toko']}'),
                trailing: Pill(r['libur_hari_ini'] == 'izin' ? 'Izin' : 'Offday', color: Colors.teal),
              ),
          ]),
        ),
      ],
      SectionHeader('Istirahat hari ini (${istirahat.length} PC)'),
      if (istirahat.isEmpty)
        const InfoBanner('Belum ada PC yang istirahat hari ini.')
      else
        Card(
          child: Column(children: [for (final r in istirahat) _breakTile(r)]),
        ),
      const SectionHeader('Peringkat PC bulan ini'),
      for (var i = 0; i < ranked.length; i++) _rankTile(i + 1, ranked[i]),
    ];
  }

  int _breakMenit(Map<String, dynamic> r) {
    final b = asMap(r['istirahat_hari_ini']);
    if (b['mulai'] == null) return 0;
    final mulai = parseWib(b['mulai'] as String);
    final selesai = b['selesai'] == null ? wibNow() : parseWib(b['selesai'] as String);
    return selesai.difference(mulai).inMinutes;
  }

  Widget _breakTile(Map<String, dynamic> r) {
    final b = asMap(r['istirahat_hari_ini']);
    final mulai = parseWib(b['mulai'] as String);
    final aktif = b['selesai'] == null;
    final menit = _breakMenit(r);
    final durasi = toNum(b['durasi_menit'] ?? 180).toInt();
    final lewat = menit > durasi;
    String jam(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    return ListTile(
      leading: Icon(aktif ? Icons.timer : Icons.free_breakfast, color: lewat ? Colors.red : (aktif ? Colors.orange : Colors.green)),
      title: Text('${r['nama']}'),
      subtitle: Text('${'${r['toko']}'.replaceFirst('OPPO Store - ', '')} · mulai ${jam(mulai)}'
          '${aktif ? ' · belum kembali' : ' · kembali ${jam(parseWib(b['selesai'] as String))}'}'),
      trailing: Wrap(spacing: 4, runSpacing: 4, children: [
        Pill(menit >= 60 ? '${menit ~/ 60}j ${menit % 60}m' : '${menit}m', color: lewat ? Colors.red.shade700 : Colors.blueGrey),
        if (b['flag'] == 'tidak_klik_kembali') Pill('Tidak klik kembali', color: Colors.red.shade700),
      ]),
      onTap: () => _openPc(r, 2),
    );
  }

  Widget _rankTile(int no, Map<String, dynamic> r) {
    final b = asMap(r['bulan']);
    final t = asMap(r['target']);
    Widget chip(String label, num a, num tg) {
      final p = pct(a, tg);
      return Pill('$label ${tg > 0 ? '${p.toStringAsFixed(0)}%' : '-'}', color: tg > 0 ? pctColor(p) : Colors.grey);
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$no')),
        title: Text('${r['nama']}'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['toko']}'),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            chip('HP', toNum(b['hp_revenue']), toNum(t['revenue_hp'])),
            chip('IoT', toNum(b['iot_unit']), toNum(t['iot_unit'])),
            chip('DB', toNum(b['db_baru']), toNum(t['database_baru'])),
          ]),
        ]),
        onTap: () => _openPc(r, 1),
      ),
    );
  }

  // -------------------------------------------------------------------
  // DATABASE
  // -------------------------------------------------------------------
  List<Widget> _database() {
    final rows = _rows;
    final totalDb = rows.fold<num>(0, (a, r) => a + toNum(asMap(r['periode'])['db_total']));
    return [
      StatGrid(children: [
        StatCard(icon: Icons.person_add, label: 'Database baru', value: angka(_sumP(rows, 'db_baru'))),
        StatCard(icon: Icons.groups, label: 'Total database', value: angka(totalDb)),
        StatCard(icon: Icons.forum, label: 'User dihubungi', value: angka(_sumP(rows, 'dihubungi_unik')), sub: '${angka(_sumP(rows, 'total_kontak'))} kali kontak'),
        StatCard(icon: Icons.error_outline, label: 'Follow up terlewat', value: angka(_sumP(rows, 'terlewat')), color: Colors.red),
      ]),
      const SectionHeader('Konversi rate per PC'),
      Text('Database yang diinput pada periode ini. Target total konversi 10:1 (10%).',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      for (final e in (_konversiPer(rows, (r) => '${r['nama']}').entries.toList()
        ..sort((a, b) => _rate(b.value[1], b.value[0]).compareTo(_rate(a.value[1], a.value[0])))))
        _konversiCard(e.key, e.value),
      const SectionHeader('Konversi rate per toko'),
      for (final e in (_konversiPer(rows, (r) => '${r['toko']}'.replaceFirst('OPPO Store - ', '')).entries.toList()
        ..sort((a, b) => _rate(b.value[1], b.value[0]).compareTo(_rate(a.value[1], a.value[0])))))
        _konversiCard(e.key, e.value),
      const SectionHeader('Per PC'),
      for (final r in rows) _dbCard(r),
    ];
  }

  static const _kKeys = ['total', 'closing', 'asking', 'asking_naik', 'probing', 'probing_naik'];

  double _rate(num a, num b) => b <= 0 ? -1 : a / b * 100;

  /// Gabungan konversi per kunci (PC atau toko): [total, closing, asking, asking_naik, probing, probing_naik]
  Map<String, List<num>> _konversiPer(List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) key) {
    final m = <String, List<num>>{};
    for (final r in rows) {
      final k = asMap(asMap(r['periode'])['konversi']);
      final v = m.putIfAbsent(key(r), () => List<num>.filled(_kKeys.length, 0));
      for (var i = 0; i < _kKeys.length; i++) {
        v[i] += toNum(k[_kKeys[i]]);
      }
    }
    return m;
  }

  Color _konversiColor(double p) {
    if (p >= 10) return Colors.green.shade700;
    if (p >= 7) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  Widget _konversiCard(String nama, List<num> v) {
    String rate(num a, num b) => b <= 0 ? '-' : '${(a / b * 100).toStringAsFixed(0)}%';
    final total = _rate(v[1], v[0]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold))),
            Pill('Total ${total < 0 ? '-' : '${total.toStringAsFixed(1)}%'}',
                color: total < 0 ? Colors.grey : _konversiColor(total)),
          ]),
          const SizedBox(height: 4),
          Text('${angka(v[0])} database · Closing ${angka(v[1])}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            Pill('Asking → Probing ${rate(v[3], v[2])} (${angka(v[3])}/${angka(v[2])})', color: statusColor('Asking')),
            Pill('Probing → Closing ${rate(v[5], v[4])} (${angka(v[5])}/${angka(v[4])})', color: statusColor('Probing')),
          ]),
        ]),
      ),
    );
  }

  Widget _dbCard(Map<String, dynamic> r) {
    final p = asMap(r['periode']);
    final b = asMap(r['bulan']);
    final st = asMap(p['status']);
    final target = toNum(asMap(r['target'])['database_baru']);
    return Card(
      child: InkWell(
        onTap: () => _openPc(r, 0),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${r['toko']}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text('Database baru ${angka(toNum(p['db_baru']))} · Dihubungi ${angka(toNum(p['dihubungi_unik']))} user (${angka(toNum(p['total_kontak']))} kali)'),
            Text('Total database ${angka(toNum(p['db_total']))} · Terlewat ${angka(toNum(p['terlewat']))}'),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final s in statusUser) Pill('$s ${angka(toNum(st[s]))}', color: statusColor(s)),
            ]),
            ProgressTile(label: 'Database baru bulan ini', actual: toNum(b['db_baru']), target: target, fmt: (v) => angka(v)),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // REPORT
  // -------------------------------------------------------------------
  List<Widget> _report() {
    final rows = _rows;
    final ids = _pcIds;
    final sales = _sales.where((s) => ids.contains(s['pc_id'])).toList();

    // Per toko
    final perToko = <String, List<num>>{};
    for (final r in rows) {
      final p = asMap(r['periode']);
      final v = perToko.putIfAbsent('${r['toko']}', () => <num>[0, 0, 0, 0]);
      v[0] += toNum(p['hp_revenue']);
      v[1] += toNum(p['hp_unit']);
      v[2] += toNum(p['iot_unit']);
      v[3] += toNum(p['iot_revenue']);
    }

    // Tren harian revenue HP
    final perHari = <String, num>{};
    if (!isSameDay(_dari, _sampai)) {
      for (var d = _dari; !d.isAfter(_sampai); d = addDays(d, 1)) {
        perHari[ymd(d)] = 0;
      }
      for (final s in sales.where((s) => s['tipe'] == 'HP')) {
        final k = '${s['tanggal']}';
        perHari[k] = (perHari[k] ?? 0) + toNum(s['subtotal']);
      }
    }

    List<MapEntry<String, num>> top(String tipe) {
      final m = <String, num>{};
      for (final s in sales.where((s) => s['tipe'] == tipe)) {
        final k = '${s['nama_produk']}';
        m[k] = (m[k] ?? 0) + toNum(s['qty']);
      }
      final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return l.take(5).toList();
    }

    return [
      StatGrid(children: [
        StatCard(icon: Icons.phone_android, label: 'Revenue HP', value: rupiah(_sumP(rows, 'hp_revenue')), sub: '${angka(_sumP(rows, 'hp_unit'))} unit'),
        StatCard(icon: Icons.watch, label: 'IoT', value: '${angka(_sumP(rows, 'iot_unit'))} unit', sub: rupiah(_sumP(rows, 'iot_revenue'))),
      ]),
      SectionHeader('Kalender NOSELL · ${namaBulan(_sampai)}'),
      _heatmap(rows),
      if (perHari.isNotEmpty) ...[
        const SectionHeader('Tren revenue HP harian'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MiniBars(data: perHari.entries.toList(), fmt: rupiah),
          ),
        ),
      ],
      const SectionHeader('Per toko'),
      Card(
        child: Column(children: [
          for (final e in perToko.entries)
            ListTile(
              title: Text(e.key.replaceFirst('OPPO Store - ', '')),
              subtitle: Text('HP ${angka(e.value[1])} unit · IoT ${angka(e.value[2])} unit (${rupiah(e.value[3])})'),
              trailing: Text(rupiah(e.value[0]), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
      ..._metodeBayar(rows, sales),
      const SectionHeader('Per PC'),
      for (final r in rows) _reportCard(r),
      for (final tipe in const ['HP', 'IOT']) ...[
        SectionHeader(tipe == 'HP' ? 'Produk HP terlaris' : 'Produk IoT terlaris'),
        Card(
          child: Column(children: [
            if (top(tipe).isEmpty) const ListTile(title: Text('Belum ada penjualan')),
            for (final e in top(tipe)) ListTile(dense: true, title: Text(e.key), trailing: Text('${angka(e.value)} unit')),
          ]),
        ),
      ],
    ];
  }

  /// Cash vs Kredit penjualan HP (berdasarkan unit) + leasing dengan kontribusi terbesar.
  List<Widget> _metodeBayar(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> sales) {
    final hp = sales.where((s) => s['tipe'] == 'HP').toList();

    Widget ringkas(String judul, String? sub, List<Map<String, dynamic>> list) {
      num cash = 0, kredit = 0, kosong = 0;
      final perLeasing = <String, num>{};
      final perCash = <String, num>{};
      for (final s in list) {
        final q = toNum(s['qty']);
        if (s['metode'] == 'Cash') {
          cash += q;
          final c = '${s['leasing'] ?? 'Lainnya'}';
          perCash[c] = (perCash[c] ?? 0) + q;
        } else if (s['metode'] == 'Kredit') {
          kredit += q;
          final l = '${s['leasing'] ?? '-'}';
          perLeasing[l] = (perLeasing[l] ?? 0) + q;
        } else {
          kosong += q;
        }
      }
      final total = cash + kredit;
      final leasing = perLeasing.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      String p(num v) => total <= 0 ? '0%' : '${(v / total * 100).round()}%';
      String pk(num v) => kredit <= 0 ? '0%' : '${(v / kredit * 100).round()}%';
      String pc(num v) => cash <= 0 ? '0%' : '${(v / cash * 100).round()}%';
      final cashVia = perCash.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 6),
          if (total <= 0)
            Text(kosong > 0 ? 'Belum ada data metode bayar ($kosong unit lama belum diisi)' : 'Belum ada penjualan HP',
                style: const TextStyle(color: Colors.grey))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  if (cash > 0) Expanded(flex: (cash * 100).round(), child: Container(color: const Color(0xFF2E7D32))),
                  if (kredit > 0) Expanded(flex: (kredit * 100).round(), child: Container(color: const Color(0xFF1565C0))),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.circle, size: 10, color: Color(0xFF2E7D32)),
              Text(' Cash ${p(cash)} (${angka(cash)} unit)   '),
              const Icon(Icons.circle, size: 10, color: Color(0xFF1565C0)),
              Text(' Kredit ${p(kredit)} (${angka(kredit)} unit)'),
            ]),
            if (cashVia.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Cash: ${cashVia.map((e) => '${e.key} ${angka(e.value)} (${pc(e.value)})').join(' · ')}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (leasing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Leasing terbesar: ${leasing.first.key} ${angka(leasing.first.value)} unit (${pk(leasing.first.value)} dari kredit)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (leasing.length > 1)
                Text(
                  leasing.skip(1).map((e) => '${e.key} ${angka(e.value)} (${pk(e.value)})').join(' · '),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
            if (kosong > 0)
              Text('$kosong unit belum diisi metode bayar (penjualan lama)',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ]),
      );
    }

    final tokoList = <String, List<String>>{};
    for (final r in rows) {
      tokoList.putIfAbsent('${r['toko']}', () => []).add(r['pc_id'] as String);
    }
    return [
      const SectionHeader('Cash vs Kredit (HP)'),
      Card(child: ringkas('Semua', '${angka(hp.fold<num>(0, (a, s) => a + toNum(s['qty'])))} unit HP', hp)),
      if (tokoList.length > 1)
        Card(
          child: Column(children: [
            for (final e in tokoList.entries)
              ringkas(e.key.replaceFirst('OPPO Store - ', ''), 'Toko', hp.where((s) => e.value.contains(s['pc_id'])).toList()),
          ]),
        ),
      Card(
        child: ExpansionTile(
          title: const Text('Per promotor'),
          children: [
            for (final r in rows)
              ringkas('${r['nama']}', '${r['toko']}'.replaceFirst('OPPO Store - ', ''),
                  hp.where((s) => s['pc_id'] == r['pc_id']).toList()),
          ],
        ),
      ),
    ];
  }

  /// Heatmap PC x tanggal bulan berjalan, diurutkan dari hari NOSELL terbanyak.
  Widget _heatmap(List<Map<String, dynamic>> rows) {
    final bulan = monthStart(_sampai);
    final data = <MapEntry<Map<String, dynamic>, Map<String, DayInfo>>>[];
    for (final r in rows) {
      final id = r['pc_id'];
      final days = computeDays(
        bulan,
        _mSales.where((s) => s['pc_id'] == id).toList(),
        _mNihil.where((s) => s['pc_id'] == id).map((s) => '${s['tanggal']}').toSet(),
        {for (final s in _mLibur.where((s) => s['pc_id'] == id)) '${s['tanggal']}': '${s['status']}'},
      );
      data.add(MapEntry(r, days));
    }
    data.sort((a, b) => daySummary(b.value).nosell.compareTo(daySummary(a.value).nosell));
    final nDays = monthEnd(bulan).day;
    const cell = 16.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(width: 120),
                for (var d = 1; d <= nDays; d++)
                  SizedBox(
                    width: cell + 2,
                    child: Text(d == 1 || d % 5 == 0 ? '$d' : '', style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                  ),
                const SizedBox(width: 8),
                const Text('NOSELL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
              ]),
              for (final e in data)
                InkWell(
                  onTap: () => _openPc(e.key, 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(
                        width: 120,
                        child: Text('${e.key['nama']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ),
                      for (final k in (e.value.keys.toList()..sort()))
                        Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: dayColors[e.value[k]!.kind],
                            borderRadius: BorderRadius.circular(3),
                            border: e.value[k]!.tidakLapor ? Border.all(color: Colors.black, width: 1.5) : null,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text('${daySummary(e.value).nosell}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text('Hijau: ada HP · Kuning: hanya IoT · Merah: NOSELL · Garis hitam: tidak lapor · Abu-abu: offday/izin atau belum lewat',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> r) {
    final p = asMap(r['periode']);
    final b = asMap(r['bulan']);
    final t = asMap(r['target']);
    return Card(
      child: InkWell(
        onTap: () => _openPc(r, 1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${r['toko']}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text('Periode: HP ${rupiah(toNum(p['hp_revenue']))} (${angka(toNum(p['hp_unit']))} unit) · IoT ${angka(toNum(p['iot_unit']))} unit'),
            ProgressTile(label: 'Revenue HP bulan ini', actual: toNum(b['hp_revenue']), target: toNum(t['revenue_hp']), fmt: rupiah),
            ProgressTile(label: 'IoT bulan ini', actual: toNum(b['iot_unit']), target: toNum(t['iot_unit']), fmt: (v) => '${angka(v)} unit'),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // ACTIVITY
  // -------------------------------------------------------------------
  List<Widget> _activity() {
    final rows = _rows;
    final lp = _leasing(rows, 'periode');
    return [
      FilledButton.tonalIcon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminGallery(
            dari: _dari,
            sampai: _sampai,
            pcNames: {for (final r in rows) r['pc_id'] as String: '${r['nama']}'},
          ),
        )),
        icon: const Icon(Icons.photo_library),
        label: const Text('Lihat galeri bukti foto'),
      ),
      const SectionHeader('Checklist standar toko hari ini'),
      Card(
        child: Column(children: [
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text('${r['nama']}'),
              subtitle: Text('${r['toko']}'.replaceFirst('OPPO Store - ', '')),
              trailing: r['libur_hari_ini'] != null
                  ? Pill(r['libur_hari_ini'] == 'izin' ? 'Izin' : 'Offday', color: Colors.teal)
                  : Pill(
                      '${angka(toNum(r['checklist_hari_ini']))}/${angka(toNum(r['checklist_item']))}',
                      color: toNum(r['checklist_hari_ini']) >= toNum(r['checklist_item']) && toNum(r['checklist_item']) > 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
              onTap: () => _openPc(r, 2),
            ),
        ]),
      ),
      const SectionHeader('Sosmed (periode)'),
      Card(
        child: Column(children: [
          for (final d in sosmedDefs)
            ListTile(
              dense: true,
              title: Text(d.label),
              subtitle: Text('Bulan ini ${angka(_sosmedB(rows, d.kode))} dari target ${angka(_sumT(rows, d.kode))}'),
              trailing: Text('${angka(_sosmedP(rows, d.kode))} ${d.satuan}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
      const SectionHeader('Leasing (periode)'),
      for (final l in leasingList) _leasingCard(l, lp[l] ?? <num>[0, 0, 0, 0]),
      const SectionHeader('Per PC'),
      for (final r in rows) _activityCard(r),
    ];
  }

  Widget _leasingCard(String l, List<num> v) {
    final avg = v[1] > 0 ? v[3] / v[1] : 0;
    final rejectRate = v[0] > 0 ? v[2] / v[0] * 100 : 0;
    return Card(
      child: ListTile(
        title: Text(l, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            Pill('Cek ${angka(v[0])}', color: Colors.blueGrey),
            Pill('Approve ${angka(v[1])}', color: Colors.green.shade700),
            Pill('Reject ${angka(v[2])}', color: Colors.red.shade700),
            Pill('Rata-rata limit ${rupiah(avg.round())}', color: Colors.indigo),
            Pill('Reject rate ${rejectRate.toStringAsFixed(0)}%', color: Colors.orange.shade800),
          ]),
        ),
      ),
    );
  }

  Widget _activityCard(Map<String, dynamic> r) {
    final p = asMap(r['periode']);
    final sos = asMap(p['sosmed']);
    final leasing = asList(p['leasing']);
    final cek = leasing.fold<num>(0, (a, x) => a + toNum(x['total']));
    final appr = leasing.fold<num>(0, (a, x) => a + toNum(x['approve']));
    return Card(
      child: InkWell(
        onTap: () => _openPc(r, 2),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['nama']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${r['toko']}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final d in sosmedDefs) Pill('${d.platform} ${d.aktivitas} ${angka(toNum(sos[d.kode]))}', color: Colors.teal),
              Pill('Cek limit ${angka(cek)} (approve ${angka(appr)})', color: Colors.indigo),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Grafik batang sederhana tanpa library.
class MiniBars extends StatelessWidget {
  final List<MapEntry<String, num>> data;
  final String Function(num) fmt;
  const MiniBars({super.key, required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final max = data.fold<num>(0, (a, e) => e.value > a ? e.value : a);
    final color = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tertinggi: ${fmt(max)}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 140,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final e in data)
            Expanded(
              child: Tooltip(
                message: '${tgl(parseDate(e.key))}: ${fmt(e.value)}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: max > 0 ? (110 * e.value / max).toDouble() : 0.0,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 4),
                  Text('${parseDate(e.key).day}', style: const TextStyle(fontSize: 8)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}
