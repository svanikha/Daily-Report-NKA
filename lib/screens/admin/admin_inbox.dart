import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../pc/pc_home.dart';

const _jenisInfo = {
  'penjualan_hp': (Icons.phone_android, Color(0xFF2E7D32), 'Penjualan'),
  'penjualan_iot': (Icons.watch, Color(0xFFF9A825), 'Penjualan'),
  'istirahat_mulai': (Icons.free_breakfast, Color(0xFFEF6C00), 'Istirahat'),
  'istirahat_selesai': (Icons.storefront, Color(0xFF00897B), 'Istirahat'),
  'leasing': (Icons.fact_check, Color(0xFF3949AB), 'Leasing'),
};

/// Pesan Masuk admin: penjualan HP/IoT, mulai/selesai istirahat, cek limit leasing.
class AdminInbox extends StatefulWidget {
  const AdminInbox({super.key});

  @override
  State<AdminInbox> createState() => _AdminInboxState();
}

class _AdminInboxState extends State<AdminInbox> {
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
        .channel('admin_inbox_page')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_events',
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
      final rows = await Session.db
          .from('admin_events')
          .select('*, profiles(id,nama,store_id,stores(nama))')
          .order('created_at', ascending: false)
          .limit(200);
      _rows = asList(rows);
      if (markRead) {
        // Status "sudah dibaca" disimpan per orang (admin dan tiap admin support terpisah).
        final me = Session.current?.id;
        final prof = me == null
            ? null
            : await Session.db.from('profiles').select('inbox_dibaca_pada').eq('id', me).maybeSingle();
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

  void _open(Map<String, dynamic> r) {
    final p = r['profiles'];
    if (p is! Map) return;
    final s = p['stores'];
    final pc = Profile(
      id: '${p['id']}',
      nama: '${p['nama']}',
      role: 'pc',
      storeId: p['store_id'] == null ? null : toNum(p['store_id']).toInt(),
      toko: s is Map ? '${s['nama']}' : '',
      email: '',
    );
    final jenis = '${r['jenis']}';
    final tab = jenis.startsWith('penjualan') ? 1 : 2;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PcHome(pc: pc, adminView: true, initialTab: tab)));
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows.where((r) => _filter == 'Semua' || _jenisInfo['${r['jenis']}']?.$3 == _filter).toList();
    final today = wibToday();
    return Scaffold(
      appBar: AppBar(title: const Text('Pesan masuk')),
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
                        for (final f in const ['Semua', 'Penjualan', 'Istirahat', 'Leasing'])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty) const EmptyState(icon: Icons.inbox, text: 'Belum ada pesan masuk'),
                    for (final r in list) _tile(r, today),
                  ]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> r, DateTime today) {
    final info = _jenisInfo['${r['jenis']}'];
    final waktu = parseWib(r['created_at'] as String);
    final jam = '${waktu.hour.toString().padLeft(2, '0')}.${waktu.minute.toString().padLeft(2, '0')}';
    final baru = _baru.contains(r['id']);
    return Card(
      color: baru ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : null,
      child: ListTile(
        onTap: () => _open(r),
        leading: CircleAvatar(
          backgroundColor: (info?.$2 ?? Colors.grey).withValues(alpha: 0.15),
          child: Icon(info?.$1 ?? Icons.notifications, color: info?.$2 ?? Colors.grey),
        ),
        title: Text('${r['judul']}', style: TextStyle(fontWeight: baru ? FontWeight.bold : FontWeight.w600)),
        subtitle: Text('${r['isi']}'),
        trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(isSameDay(dateOnly(waktu), today) ? jam : '${tglPendek(waktu)}\n$jam',
              textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall),
          if (baru) Padding(padding: const EdgeInsets.only(top: 4), child: Pill('Baru', color: Colors.red.shade700)),
        ]),
      ),
    );
  }
}
