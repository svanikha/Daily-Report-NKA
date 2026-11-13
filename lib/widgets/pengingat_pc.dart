import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../data/nka.dart';
import '../services/session.dart';
import '../utils.dart';
import 'status_online.dart';
import 'widgets.dart';

/// Kegiatan yang bisa diingatkan ke PC (kode sama dengan fungsi SQL label_modul).
const pengingatModul = <String, String>{
  'stok': 'Update stok',
  'penjualan': 'Input penjualan',
  'ms_allbrand': 'MS Allbrand',
  'display': 'Cek display',
  'sosmed': 'Activity sosmed',
  'leasing': 'Cek limit leasing',
  'laporan': 'Kirim laporan',
  'istirahat': 'Kembali dari istirahat',
};

/// Kegiatan yang belum dikerjakan PC, dari baris status_toko (untuk pilihan awal pengingat).
List<String> pengingatBelum(Map<String, dynamic> t) => [
      if (t['stok_waktu'] == null) 'stok',
      if (toNum(t['unit']) <= 0 && toNum(t['iot']) <= 0 && t['nihil'] != true) 'penjualan',
      if (t['kompetitor_terisi'] != true) 'ms_allbrand',
      if (t['display_terisi'] != true) 'display',
      if (t['laporan_pada'] == null) 'laporan',
      if (t['istirahat'] != null && asMap(t['istirahat'])['selesai'] == null) 'istirahat',
    ];

/// TL / Trainer / PIC: kirim pengingat ke PC toko. Masuk sebagai push ke HP PC.
Future<void> showKirimPengingat(
  BuildContext context, {
  required int storeId,
  required String toko,
  String? pcNama,
  List<String> pilihAwal = const [],
}) async {
  final pilih = <String>{...pilihAwal};
  final pesan = TextEditingController();
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Ingatkan ${pcNama ?? 'PC'}', style: Theme.of(ctx).textTheme.titleLarge),
            Text(toko, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            const Text('Kegiatan yang harus segera dikerjakan', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in pengingatModul.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: pilih.contains(e.key),
                  onSelected: (v) => setS(() => v ? pilih.add(e.key) : pilih.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: pesan,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Pesan tambahan (opsional)'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (pilih.isEmpty && pesan.text.trim().isEmpty) {
                        showMsg(ctx, 'Pilih kegiatan atau tulis pesan');
                        return;
                      }
                      setS(() => busy = true);
                      try {
                        final r = asMap(await Session.db.rpc('kirim_pengingat', params: {
                          'p_store': storeId,
                          'p_modul': [for (final k in pengingatModul.keys) if (pilih.contains(k)) k],
                          'p_pesan': pesan.text.trim(),
                        }));
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (context.mounted) {
                          showMsg(
                              context,
                              r['punya_hp'] == true
                                  ? 'Pengingat terkirim ke ${r['pc']}'
                                  : 'Pengingat tersimpan. HP ${r['pc']} belum terdaftar push, '
                                      'pengingat tampil saat PC membuka aplikasi versi terbaru.');
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setS(() => busy = false);
                          showErr(ctx, e);
                        }
                      }
                    },
              icon: busyIcon(busy, Icons.notifications_active),
              label: const Text('Kirim pengingat'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 16),
            RiwayatPengingat(storeId: storeId),
          ]),
        ),
      ),
    ),
  );
  pesan.dispose();
}

/// Kartu di beranda PC: pengingat dari atasan yang belum ditandai dibaca.
class PengingatPcCard extends StatefulWidget {
  const PengingatPcCard({super.key});

  @override
  State<PengingatPcCard> createState() => _PengingatPcCardState();
}

class _PengingatPcCardState extends State<PengingatPcCard> {
  List<Map<String, dynamic>> _list = [];
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    final me = Session.current;
    if (me == null) return;
    _ch = Session.db
        .channel('pengingat_${me.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pengingat',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'pc_id', value: me.id),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final c = _ch;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
  }

  Future<void> _load() async {
    final me = Session.current;
    if (me == null) return;
    try {
      final rows = asList(await Session.db
          .from('pengingat')
          .select('id,pesan,created_at,profiles!pengingat_dari_fkey(nama,role)')
          .eq('pc_id', me.id)
          .isFilter('dibaca_pada', null)
          .order('created_at', ascending: false)
          .limit(10));
      if (mounted) setState(() => _list = rows);
    } catch (_) {}
  }

  /// Balas "Siap 👍" (satu pengingat, atau semua jika id null). Atasan menerima notifikasi.
  Future<void> _siap([String? id]) async {
    setState(() => _list = id == null ? [] : _list.where((r) => '${r['id']}' != id).toList());
    try {
      await Session.db.rpc('respon_pengingat', params: {'p_id': id, 'p_respon': 'Siap'});
    } catch (_) {
      // Server belum mendukung balasan (tahap2f.sql): cukup tandai dibaca
      try {
        await Session.db.rpc('baca_pengingat', params: {'p_id': id});
      } catch (_) {}
    }
    if (mounted) showMsg(context, 'Balasan "Siap 👍" terkirim ke atasan');
    _load();
  }

  String _dari(Map<String, dynamic> r) {
    final p = asMap(r['profiles']);
    final peran = switch ('${p['role']}') { 'tl' => 'TL', 'trainer' => 'Trainer', _ => 'PIC NKA' };
    return '${p['nama'] ?? 'Atasan'} ($peran)';
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox.shrink();
    final c = Colors.deepOrange.shade700;
    return Card(
      color: Colors.deepOrange.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.notifications_active, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text('Pesan dari atasan', style: TextStyle(fontWeight: FontWeight.bold, color: c))),
            if (_list.length > 1) TextButton(onPressed: () => _siap(), child: const Text('Siap semua 👍')),
          ]),
          for (final r in _list)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['pesan']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text('${_dari(r)} · ${waktuSingkat(parseWib('${r['created_at']}'))}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _siap('${r['id']}'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Siap 👍'),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Atasan: pengingat terakhir ke toko ini beserta status (belum dibaca / dibaca / Siap 👍).
class RiwayatPengingat extends StatefulWidget {
  final int storeId;
  const RiwayatPengingat({super.key, required this.storeId});

  @override
  State<RiwayatPengingat> createState() => _RiwayatPengingatState();
}

class _RiwayatPengingatState extends State<RiwayatPengingat> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = asList(await Session.db
          .from('pengingat')
          .select('id,pesan,created_at,dibaca_pada,respon,respon_pada,push_ok,profiles!pengingat_dari_fkey(nama)')
          .eq('store_id', widget.storeId)
          .order('created_at', ascending: false)
          .limit(5));
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Pengingat terakhir', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      for (final r in rows) _row(r),
    ]);
  }

  Widget _row(Map<String, dynamic> r) {
    final String status;
    final Color c;
    final IconData ic;
    if (r['respon'] != null) {
      status = '${r['respon']} 👍 ${r['respon_pada'] == null ? '' : jamMenit(parseWib('${r['respon_pada']}'))}';
      c = Colors.green.shade700;
      ic = Icons.done_all;
    } else if (r['dibaca_pada'] != null) {
      status = 'Dibaca';
      c = Colors.blue.shade700;
      ic = Icons.done_all;
    } else if (r['push_ok'] == false) {
      status = 'HP PC belum terdaftar';
      c = Colors.orange.shade800;
      ic = Icons.phonelink_off;
    } else {
      status = 'Terkirim';
      c = Colors.grey.shade600;
      ic = Icons.done;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['pesan']}', style: const TextStyle(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text('${asMap(r['profiles'])['nama'] ?? ''} · ${waktuSingkat(parseWib('${r['created_at']}'))}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
        ),
        const SizedBox(width: 6),
        Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
      ]),
    );
  }
}
