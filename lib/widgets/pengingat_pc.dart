import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

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

  Future<void> _baca([String? id]) async {
    try {
      await Session.db.rpc('baca_pengingat', params: {'p_id': id});
    } catch (_) {}
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
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.notifications_active, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text('Pengingat dari atasan', style: TextStyle(fontWeight: FontWeight.bold, color: c))),
            if (_list.length > 1) TextButton(onPressed: () => _baca(), child: const Text('Oke semua')),
          ]),
          for (final r in _list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${r['pesan']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${_dari(r)} · ${waktuSingkat(parseWib('${r['created_at']}'))}'),
              trailing: TextButton(onPressed: () => _baca('${r['id']}'), child: const Text('Oke')),
            ),
        ]),
      ),
    );
  }
}
