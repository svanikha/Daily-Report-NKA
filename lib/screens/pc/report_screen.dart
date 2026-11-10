import 'package:flutter/material.dart';

import '../../data/targets.dart';
import '../../services/pc_sync.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/nosell_calendar.dart';
import '../../widgets/widgets.dart';
import 'sale_form.dart';

class ReportScreen extends StatelessWidget {
  final Profile pc;
  final bool adminView;
  const ReportScreen({super.key, required this.pc, this.adminView = false});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: pcAppBar(
          context,
          'Report',
          pc,
          adminView,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Revenue HP'), Tab(text: 'IoT'), Tab(text: 'Kalender')],
          ),
        ),
        body: TabBarView(children: [
          SalesTab(pc: pc, tipe: 'HP', adminView: adminView),
          SalesTab(pc: pc, tipe: 'IOT', adminView: adminView),
          NosellCalendar(pc: pc, adminView: adminView),
        ]),
      ),
    );
  }
}

class SalesTab extends StatefulWidget {
  final Profile pc;
  final String tipe; // HP | IOT
  final bool adminView;
  const SalesTab({super.key, required this.pc, required this.tipe, this.adminView = false});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sales = [];
  Map<String, num> _targets = {};
  bool _nihilToday = false;

  bool get _isHp => widget.tipe == 'HP';

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
            .from('sales')
            .select()
            .eq('pc_id', widget.pc.id)
            .eq('tipe', widget.tipe)
            .gte('tanggal', ymd(monthStart()))
            .lte('tanggal', ymd(monthEnd()))
            .order('tanggal', ascending: false)
            .order('created_at', ascending: false),
        loadTargets(widget.pc.id, monthStart()),
        db.from('checkins').select('modul').eq('pc_id', widget.pc.id).eq('tanggal', todayStr()).eq('modul', 'report'),
      ]);
      _sales = asList(res[0]);
      _targets = res[1] as Map<String, num>;
      _nihilToday = asList(res[2]).isNotEmpty;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SaleForm(pc: widget.pc, tipe: widget.tipe),
    ));
    if (ok == true) {
      _load();
      PcSync.refresh();
    }
  }

  Future<void> _nihil() async {
    final ok = await confirmDialog(context, 'Laporkan nihil?', 'Tandai bahwa hari ini tidak ada penjualan HP maupun IoT.');
    if (!ok) return;
    try {
      await Session.db.from('checkins').upsert(
        {'pc_id': widget.pc.id, 'tanggal': todayStr(), 'modul': 'report'},
        onConflict: 'pc_id,tanggal,modul',
      );
      PcSync.refresh();
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await confirmDialog(context, 'Hapus transaksi?', '${s['nama_produk']} x${s['qty']}', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('sales').delete().eq('id', s['id'] as String);
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
    final todayRows = _sales.where((s) => s['tanggal'] == today);
    final rpToday = todayRows.fold<num>(0, (a, s) => a + toNum(s['subtotal']));
    final unitToday = todayRows.fold<num>(0, (a, s) => a + toNum(s['qty']));
    final rpMonth = _sales.fold<num>(0, (a, s) => a + toNum(s['subtotal']));
    final unitMonth = _sales.fold<num>(0, (a, s) => a + toNum(s['qty']));
    final target = _isHp ? (_targets['revenue_hp'] ?? 0) : (_targets['iot_unit'] ?? 0);
    final actual = _isHp ? rpMonth : unitMonth;
    final sisa = (target - actual) > 0 ? target - actual : 0;
    final perHari = sisa / sisaHari();
    String fmt(num v) => _isHp ? rupiah(v) : '${angka(v.round())} unit';

    // Rincian per seri / jenis
    final perGrup = <String, List<num>>{};
    for (final s in _sales) {
      final g = '${s['grup'] ?? '-'}';
      final v = perGrup.putIfAbsent(g, () => [0, 0]);
      v[0] += toNum(s['qty']);
      v[1] += toNum(s['subtotal']);
    }
    // Kelompok per tanggal
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final s in _sales) {
      byDate.putIfAbsent('${s['tanggal']}', () => []).add(s);
    }
    // Penjualan bisa ditambah kapan saja, termasuk untuk tanggal lampau.
    final canAdd = !widget.adminView;

    return Scaffold(
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add_${widget.tipe}',
              onPressed: _add,
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(_isHp ? 'Penjualan HP' : 'Penjualan IoT'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                    if (!widget.adminView)
                      const InfoBanner('Penjualan bisa diisi untuk tanggal berapa pun sampai hari ini. Pilih tanggal di form.',
                          icon: Icons.event_available),
                    StatGrid(children: [
                      StatCard(
                        icon: Icons.today,
                        label: 'Hari ini',
                        value: _isHp ? rupiah(rpToday) : '${angka(unitToday)} unit',
                        sub: _isHp ? '${angka(unitToday)} unit' : rupiah(rpToday),
                      ),
                      StatCard(
                        icon: Icons.calendar_month,
                        label: 'Bulan ini',
                        value: _isHp ? rupiah(rpMonth) : '${angka(unitMonth)} unit',
                        sub: _isHp ? '${angka(unitMonth)} unit' : rupiah(rpMonth),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ProgressTile(
                            label: _isHp ? 'Pencapaian revenue HP' : 'Pencapaian IoT (unit)',
                            actual: actual,
                            target: target,
                            fmt: fmt,
                          ),
                          if (target > 0) ...[
                            const Divider(),
                            _row('Sisa target', fmt(sisa)),
                            _row('Sisa hari (termasuk hari ini)', '${sisaHari()} hari'),
                            _row('Kebutuhan per hari', _isHp ? rupiah(perHari.round()) : '${perHari.toStringAsFixed(1)} unit'),
                          ],
                        ]),
                      ),
                    ),
                    if (!widget.adminView && pcInputOpen() && todayRows.isEmpty && !_nihilToday)
                      OutlinedButton.icon(
                        onPressed: _nihil,
                        icon: const Icon(Icons.do_not_disturb_on_outlined),
                        label: const Text('Laporkan nihil (tidak ada penjualan hari ini)'),
                      ),
                    if (_nihilToday && todayRows.isEmpty)
                      const InfoBanner('Hari ini sudah dilaporkan nihil.', icon: Icons.check_circle, color: Colors.green),
                    if (perGrup.isNotEmpty) ...[
                      SectionHeader(_isHp ? 'Rincian per seri (bulan ini)' : 'Rincian per jenis (bulan ini)'),
                      Card(
                        child: Column(children: [
                          for (final e in perGrup.entries)
                            ListTile(
                              dense: true,
                              title: Text(e.key),
                              trailing: Text('${angka(e.value[0])} unit · ${rupiah(e.value[1])}'),
                            ),
                        ]),
                      ),
                    ],
                    const SectionHeader('Transaksi bulan ini'),
                    if (_sales.isEmpty) const EmptyState(icon: Icons.receipt_long, text: 'Belum ada transaksi bulan ini'),
                    for (final e in byDate.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          '${hariTgl(parseDate(e.key))} · ${rupiah(e.value.fold<num>(0, (a, s) => a + toNum(s['subtotal'])))}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final s in e.value)
                        Card(
                          child: ListTile(
                            title: Text('${s['nama_produk']}'),
                            subtitle: Text('${s['qty']} x ${rupiah(toNum(s['harga']))}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(rupiah(toNum(s['subtotal'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (adminCanEdit(widget.adminView) || canPcEditSale('${s['tanggal']}'))
                                IconButton(onPressed: () => _delete(s), icon: const Icon(Icons.delete_outline)),
                            ]),
                          ),
                        ),
                    ],
                  ]),
                ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
