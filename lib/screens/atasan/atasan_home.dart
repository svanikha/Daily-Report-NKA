import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../data/nka.dart';
import '../../services/akun.dart';
import '../../services/push_service.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../utils.dart';
import '../../widgets/kalender_penjualan.dart';
import '../../widgets/sell_out_card.dart';
import '../../widgets/widgets.dart';
import 'aktivitas_screen.dart';
import 'checklist_screen.dart';
import 'offday_screen.dart';
import 'produk_screen.dart';
import 'target_screen.dart';
import 'toko_detail_screen.dart';

/// Beranda TL, Trainer, dan PIC NKA: status laporan semua toko di cakupannya + menu kelola.
class AtasanHome extends StatefulWidget {
  const AtasanHome({super.key});

  @override
  State<AtasanHome> createState() => _AtasanHomeState();
}

class _AtasanHomeState extends State<AtasanHome> {
  int _tab = 0;
  DateTime _tanggal = wibToday();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _toko = [];
  int _unread = 0;
  RealtimeChannel? _channel;

  Profile get me => Session.current!;

  @override
  void initState() {
    super.initState();
    // Push diketuk saat aplikasi di latar belakang / tertutup -> buka Aktivitas
    PushService.onOpenInbox = () {
      if (mounted) _bukaAktivitas();
    };
    PushService.registerAdmin();
    _load();
    _loadUnread();
    _channel = Session.db
        .channel('aktivitas_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'aktivitas',
          callback: (_) {
            _loadUnread();
            if (_tab == 0) _load();
          },
        )
        .subscribe();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.check(context);
    });
  }

  @override
  void dispose() {
    PushService.onOpenInbox = null;
    final c = _channel;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final n = toNum(await Session.db.rpc('my_inbox_unread')).toInt();
      if (mounted) setState(() => _unread = n);
    } catch (_) {}
  }

  Future<void> _bukaAktivitas() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AktivitasScreen()));
    _loadUnread();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _toko.isEmpty;
      _error = null;
    });
    try {
      _toko = asList(await Session.db.rpc('status_toko', params: {'p_tanggal': ymd(_tanggal)}));
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2026, 1, 1),
      lastDate: wibToday(),
      helpText: 'Tanggal laporan',
    );
    if (d != null) {
      setState(() => _tanggal = dateOnly(d));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cakupan = me.isPic ? 'Semua area' : 'Area ${me.area}';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tab == 0 ? 'Laporan toko' : 'Kelola'),
          Text('${me.nama} · ${me.roleLabel} · $cakupan', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          IconButton(
            onPressed: _bukaAktivitas,
            tooltip: 'Aktivitas toko',
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              child: const Icon(Icons.notifications),
            ),
          ),
          if (_tab == 0) ...[
            IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), tooltip: 'Pilih tanggal'),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
          ],
          const AkunMenuButton(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Toko'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Kelola'),
        ],
      ),
      body: _tab == 0 ? _tokoTab() : _kelolaTab(),
    );
  }

  // ------------------------------------------------------------------
  Widget _tokoTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final hariIni = isSameDay(_tanggal, wibToday());
    final lewatBatas = !hariIni || lewatBatasLaporan();
    final wajib = _toko.where((t) => t['libur'] == null && t['punya_pc'] != false).toList();
    final terkirim = wajib.where((t) => t['laporan_pada'] != null).length;
    final stokOk = wajib.where((t) => t['stok_waktu'] != null).length;
    final unit = _toko.fold<num>(0, (a, t) => a + toNum(t['unit']));
    final value = _toko.fold<num>(0, (a, t) => a + toNum(t['value']));
    final komp = _toko.fold<num>(0, (a, t) => a + toNum(t['kompetitor_unit']));
    final unitBulan = _toko.fold<num>(0, (a, t) => a + toNum(t['unit_bulan']));
    final targetUnit = _toko.fold<num>(0, (a, t) => a + toNum(t['target_unit']));
    final valueBulan = _toko.fold<num>(0, (a, t) => a + toNum(t['value_bulan']));
    final targetValue = _toko.fold<num>(0, (a, t) => a + toNum(t['target_value']));

    final hk = HariKerja.dari(_tanggal);

    final out = <Widget>[
      TimegoneBar(hk: hk, tampilSisa: false),
      KalenderPenjualan(
        key: ValueKey('kal-${_toko.length}'),
        selected: _tanggal,
        toko: _toko,
        onSelect: (d) {
          setState(() => _tanggal = d);
          _load();
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text('Laporan ${hariTgl(_tanggal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      StatGrid(children: [
        StatCard(label: 'Laporan terkirim', value: '$terkirim/${wajib.length}', sub: 'PC wajib lapor', icon: Icons.verified),
        StatCard(label: 'Stok diupdate', value: '$stokOk/${wajib.length}', sub: 'toko wajib lapor', icon: Icons.inventory_2),
        StatCard(label: 'Sell-out HP', value: '${angka(unit)} unit', sub: rupiah(value), icon: Icons.smartphone),
        StatCard(
          label: 'MS Allbrand',
          value: unit + komp > 0 ? '${(unit / (unit + komp) * 100).toStringAsFixed(0)}%' : '-',
          sub: 'OPPO ${angka(unit)} · brand lain ${angka(komp)}',
          icon: Icons.pie_chart,
        ),
      ]),
      Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(children: [
            ProgressTile(
              label: me.isTl ? 'Pencapaian TL (unit HP, bulan ini)' : 'Unit HP bulan ini',
              actual: unitBulan,
              target: targetUnit,
              fmt: (v) => '${angka(v)} unit',
            ),
            ProgressTile(
              label: me.isTl ? 'Pencapaian TL (value HP, bulan ini)' : 'Value HP bulan ini',
              actual: valueBulan,
              target: targetValue,
              fmt: rupiah,
            ),
          ]),
        ),
      ),
    ];

    String? area;
    for (final t in _toko) {
      if (t['area'] != area) {
        area = '${t['area']}';
        out.add(SectionHeader('Area $area'));
      }
      out.add(_tokoCard(t, lewatBatas));
    }
    if (_toko.isEmpty) out.add(const EmptyState(text: 'Tidak ada toko di cakupan akun ini', icon: Icons.store));

    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: out));
  }

  Widget _tokoCard(Map<String, dynamic> t, bool lewatBatas) {
    final libur = t['libur'] as String?;
    final nonPc = t['punya_pc'] == false;
    final stok = t['stok_waktu'] == null ? null : parseWib('${t['stok_waktu']}');
    final lap = t['laporan_pada'] == null ? null : parseWib('${t['laporan_pada']}');
    final ist = t['istirahat'] == null ? null : asMap(t['istirahat']);

    Widget laporanPill;
    if (lap != null) {
      laporanPill = Pill('Lapor ${jamMenit(lap)}', color: Colors.green.shade700);
    } else if (libur != null) {
      laporanPill = Pill(libur == 'izin' ? 'Izin' : 'Offday', color: Colors.teal);
    } else if (lewatBatas) {
      laporanPill = Pill('Tidak lapor', color: Colors.red.shade700);
    } else {
      laporanPill = Pill('Belum lapor', color: Colors.grey.shade700);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TokoDetailScreen(toko: TokoHari.dariStatus(t, _tanggal)),
          ));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['toko']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(nonPc ? 'Non PC (diinput TL)' : 'PC: ${t['pc'] ?? '-'}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              if (!nonPc) laporanPill,
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(
                stok == null ? 'Stok belum' : 'Stok ${jamMenit(stok)}',
                stok != null,
              ),
              _chip(
                toNum(t['unit']) > 0 || toNum(t['iot']) > 0
                    ? 'HP ${angka(toNum(t['unit']))} · IoT ${angka(toNum(t['iot']))}'
                    : (t['nihil'] == true ? 'NOSELL' : 'Jual belum'),
                toNum(t['unit']) > 0 || toNum(t['iot']) > 0 || t['nihil'] == true,
              ),
              _chip(
                t['kompetitor_terisi'] == true ? 'MS ${angka(toNum(t['kompetitor_unit']))}' : 'MS belum',
                t['kompetitor_terisi'] == true,
              ),
              _chip(t['display_terisi'] == true ? 'Display ✓' : 'Display belum', t['display_terisi'] == true),
              if (ist != null) _istirahatChip(ist),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String text, bool ok, {bool warn = false}) =>
      Pill(text, color: !ok ? Colors.grey.shade600 : (warn ? Colors.orange.shade800 : Colors.green.shade700));

  Widget _istirahatChip(Map<String, dynamic> b) {
    final mulai = parseWib('${b['mulai']}');
    final durasi = toNum(b['durasi_menit']).toInt();
    if (b['selesai'] == null) {
      final lewat = wibNow().difference(mulai).inMinutes - durasi;
      return Pill(lewat > 0 ? 'Istirahat telat $lewat mnt' : 'Istirahat sejak ${jamMenit(mulai)}',
          color: lewat > 0 ? Colors.red.shade700 : Colors.amber.shade900);
    }
    final telat = toNum(b['terlambat_menit']).toInt();
    return Pill(telat > 0 ? 'Istirahat telat $telat mnt' : 'Istirahat OK',
        color: telat > 0 ? Colors.red.shade700 : Colors.green.shade700);
  }

  // ------------------------------------------------------------------
  Widget _kelolaTab() {
    final bisaAtur = me.isPic || me.isTrainer;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (!bisaAtur)
        const InfoBanner('Jadwal offday, produk & harga, dan target diatur oleh Trainer dan PIC NKA.'),
      if (bisaAtur) ...[
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_busy),
            title: const Text('Jadwal offday & izin PC'),
            subtitle: Text(me.isPic ? 'Semua area' : 'PC area ${me.area}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const OffdayScreen()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sell),
            title: const Text('Produk & harga'),
            subtitle: const Text('Tambah produk HP/IoT, ubah harga, tipe fokus'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const ProdukScreen()),
          ),
        ),
      ],
      Card(
        child: ListTile(
          leading: const Icon(Icons.checklist),
          title: const Text('Checklist display'),
          subtitle: const Text('Tambah, ubah, urutkan item cek display PC'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => go(const ChecklistScreen()),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.flag),
          title: const Text('Target bulanan toko'),
          subtitle: Text(bisaAtur ? 'Atur target unit, value, tipe fokus, IoT' : 'Lihat target toko di area'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => go(const TargetScreen()),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Ganti password'),
          onTap: () => changePasswordDialog(context),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Keluar'),
          onTap: () => logout(context),
        ),
      ),
      const SizedBox(height: 12),
      Center(child: Text('Daily Report NKA · versi ${UpdateService.versionName}', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}
