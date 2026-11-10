import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import 'toko_detail_screen.dart';

/// (ikon, warna, kelompok filter) per jenis aktivitas.
const _jenisInfo = {
  'penjualan_hp': (Icons.smartphone, Color(0xFF2E7D32), 'Penjualan'),
  'penjualan_iot': (Icons.watch, Color(0xFFF9A825), 'Penjualan'),
  'hapus_penjualan': (Icons.delete_outline, Color(0xFF757575), 'Penjualan'),
  'nosell': (Icons.money_off, Color(0xFFC62828), 'Penjualan'),
  'stok': (Icons.inventory_2, Color(0xFF3949AB), 'Stok'),
  'ms_allbrand': (Icons.pie_chart, Color(0xFF6A1B9A), 'MS Allbrand'),
  'display': (Icons.storefront, Color(0xFF00838F), 'Display'),
  'laporan': (Icons.verified, Color(0xFF1B5E20), 'Laporan'),
  'istirahat_mulai': (Icons.free_breakfast, Color(0xFFEF6C00), 'Istirahat'),
  'istirahat_selesai': (Icons.storefront, Color(0xFF00897B), 'Istirahat'),
  'istirahat_telat': (Icons.alarm, Color(0xFFC62828), 'Istirahat'),
};

const _filters = ['Semua', 'Penjualan', 'Istirahat', 'Stok', 'MS Allbrand', 'Display', 'Laporan'];

/// Aktivitas semua toko di cakupan akun (TL: areanya, Trainer: areanya, PIC: semua),
/// bertambah langsung tanpa refresh. Ketuk untuk membuka laporan toko pada tanggal itu.
class AktivitasScreen extends StatefulWidget {
  const AktivitasScreen({super.key});

  @override
  State<AktivitasScreen> createState() => _AktivitasScreenState();
}

class _AktivitasScreenState extends State<AktivitasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _baru = {};
  String _filter = 'Semua';
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load(markRead: true);
    _channel = Session.db
        .channel('aktivitas_page')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'aktivitas',
          callback: (_) => _load(markRead: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final c = _channel;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
  }

  Future<void> _load({bool markRead = false}) async {
    try {
      _rows = asList(await Session.db
          .from('aktivitas')
          .select('id,store_id,jenis,judul,isi,tanggal,created_at,oleh,stores(nama,punya_pc,areas(nama))')
          .order('created_at', ascending: false)
          .limit(300));
      if (markRead) {
        final prof = await Session.db.from('profiles').select('inbox_dibaca_pada').eq('id', Session.current!.id).maybeSingle();
        final lastRaw = prof?['inbox_dibaca_pada'];
        final last = lastRaw == null ? null : DateTime.parse(lastRaw as String);
        _baru.addAll(_rows
            .where((r) => last == null || DateTime.parse(r['created_at'] as String).isAfter(last))
            .map((r) => r['id'] as String));
        await Session.db.rpc('set_inbox_dibaca');
      }
      _error = null;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final s = asMap(r['stores']);
    final storeId = toNum(r['store_id']).toInt();
    String? pcId;
    String? pcNama;
    try {
      final pc = await Session.db
          .from('profiles')
          .select('id,nama')
          .eq('store_id', storeId)
          .eq('role', 'pc')
          .eq('aktif', true)
          .limit(1)
          .maybeSingle();
      pcId = pc?['id'] as String?;
      pcNama = pc?['nama'] as String?;
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TokoDetailScreen(
        toko: TokoHari(
          storeId: storeId,
          toko: '${s['nama'] ?? ''}',
          area: '${asMap(s['areas'])['nama'] ?? ''}',
          pcId: pcId,
          pcNama: pcNama,
          punyaPc: s['punya_pc'] != false,
          tanggal: parseDate('${r['tanggal']}'),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => _filter == 'Semua' || _jenisInfo['${r['jenis']}']?.$3 == _filter).toList();
    final today = wibToday();
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivitas toko')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: () => _load())
              : RefreshIndicator(
                  onRefresh: () => _load(markRead: true),
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final f in _filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty) const EmptyState(icon: Icons.notifications_none, text: 'Belum ada aktivitas'),
                    for (final r in list) _tile(r, today),
                  ]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> r, DateTime today) {
    final info = _jenisInfo['${r['jenis']}'];
    final waktu = parseWib(r['created_at'] as String);
    final baru = _baru.contains(r['id']);
    final warna = info?.$2 ?? Colors.grey;
    return Card(
      color: baru ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : null,
      child: ListTile(
        onTap: () => _open(r),
        leading: CircleAvatar(backgroundColor: warna.withValues(alpha: 0.15), child: Icon(info?.$1 ?? Icons.notifications, color: warna)),
        title: Text('${r['judul']}', style: TextStyle(fontWeight: baru ? FontWeight.bold : FontWeight.w600)),
        subtitle: Text('${r['isi']}'),
        trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(isSameDay(dateOnly(waktu), today) ? jamMenit(waktu) : '${tglPendek(waktu)}\n${jamMenit(waktu)}',
              textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall),
          if (baru) Padding(padding: const EdgeInsets.only(top: 4), child: Pill('Baru', color: Colors.red.shade700)),
        ]),
      ),
    );
  }
}
