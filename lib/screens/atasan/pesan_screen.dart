import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../data/nka.dart';
import '../../services/presence_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/avatar.dart';
import '../../widgets/status_online.dart';
import '../../widgets/widgets.dart';

String _peran(String? r) => switch (r) { 'tl' => 'TL', 'trainer' => 'Trainer', 'pic' => 'PIC NKA', _ => '' };

/// Daftar kontak TL, Trainer, dan PIC NKA untuk pesan pribadi 1 lawan 1.
class PesanKontakScreen extends StatefulWidget {
  /// Buka langsung percakapan dengan orang ini (dari push).
  final String? bukaDari;
  const PesanKontakScreen({super.key, this.bukaDari});

  @override
  State<PesanKontakScreen> createState() => _PesanKontakScreenState();
}

class _PesanKontakScreenState extends State<PesanKontakScreen> {
  List<Map<String, dynamic>> _kontak = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  RealtimeChannel? _ch;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Perbarui lampu online setiap 1 menit
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    _load().then((_) {
      final id = widget.bukaDari;
      if (id == null || !mounted) return;
      final k = _kontak.where((k) => '${k['id']}' == id).toList();
      if (k.isNotEmpty) _buka(k.first);
    });
    _ch = Session.db
        .channel('pesan_kontak_${Session.current?.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pesan_atasan',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final c = _ch;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
  }

  Future<void> _hapusSemua() async {
    final ok = await confirmDialog(
      context,
      'Hapus semua riwayat chat?',
      'SEMUA pesan antar TL, Trainer, PIC, dan Manajer Trainer (milik semua orang) akan dihapus permanen. '
          'Tindakan ini tidak bisa dibatalkan.',
      yes: 'Hapus semua',
    );
    if (!ok) return;
    try {
      final n = toNum(await Session.db.rpc('hapus_semua_pesan')).toInt();
      if (mounted) showMsg(context, ' pesan dihapus');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _load() async {
    try {
      _kontak = asList(await Session.db.rpc('kontak_atasan'));
      _error = null;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _buka(Map<String, dynamic> k) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PesanChatScreen(kontak: k)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = _kontak
        .where((k) => q.isEmpty || '${k['nama']} ${(k['jabatan'] as String? ?? _peran(k['role'] as String?))} ${k['area'] ?? ''}'.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan'),
        actions: [
          if (Session.current?.isPic ?? false)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'hapus') _hapusSemua();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'hapus',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
                    title: Text('Hapus semua riwayat chat', style: TextStyle(color: Colors.red.shade700)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    const InfoBanner('Pesan pribadi antar TL, Trainer, dan PIC NKA. Hanya kamu dan penerima yang bisa membaca.',
                        icon: Icons.lock_outline),
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari nama...', isDense: true),
                      onChanged: (v) => setState(() => _q = v.trim()),
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty) const EmptyState(icon: Icons.people, text: 'Tidak ada kontak'),
                    for (final k in list) _tile(k),
                  ]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> k) {
    final belum = toNum(k['belum_dibaca']).toInt();
    final pada = k['terakhir_pada'] == null ? null : parseWib('${k['terakhir_pada']}');
    final nama = '${k['nama']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () => _buka(k),
        leading: Stack(clipBehavior: Clip.none, children: [
          AvatarProfil(url: k['foto_url'] as String?, nama: nama),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: LampuOnline(online: StatusOnline.dari(k, parseWib).online, size: 11),
            ),
          ),
        ]),
        title: Row(children: [
          Flexible(
            child: Text(nama,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: belum > 0 ? FontWeight.bold : FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(StatusOnline.dari(k, parseWib).online ? 'Online' : 'Offline',
              style: TextStyle(
                  fontSize: 11,
                  color: StatusOnline.dari(k, parseWib).online ? Colors.green.shade700 : Colors.red.shade700)),
        ]),
        subtitle: Text(
          k['terakhir'] != null
              ? '${k['terakhir']}'
              : '${(k['jabatan'] as String? ?? _peran(k['role'] as String?))}${k['area'] != null ? ' · ${k['area']}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (pada != null) Text(waktuSingkat(pada), style: Theme.of(context).textTheme.bodySmall),
          if (belum > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(10)),
              child: Text('$belum', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ]),
      ),
    );
  }
}

/// Percakapan pribadi dengan satu atasan.
class PesanChatScreen extends StatefulWidget {
  final Map<String, dynamic> kontak;
  const PesanChatScreen({super.key, required this.kontak});

  @override
  State<PesanChatScreen> createState() => _PesanChatScreenState();
}

class _PesanChatScreenState extends State<PesanChatScreen> {
  final _isi = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _kirim = false;
  RealtimeChannel? _ch;
  Timer? _timer;
  late StatusOnline _status = StatusOnline.dari(widget.kontak, parseWib);

  String get _lawan => '${widget.kontak['id']}';
  String get _me => Session.current!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _cekStatus();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _cekStatus());
    _ch = Session.db
        .channel('pesan_chat_${_me}_$_lawan')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pesan_atasan',
          callback: (p) {
            final r = p.newRecord;
            if ('${r['dari']}' == _lawan || '${r['ke']}' == _lawan) _load();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final c = _ch;
    if (c != null) Session.db.removeChannel(c);
    _isi.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _rows = asList(await Session.db
          .from('pesan_atasan')
          .select('id,dari,ke,isi,created_at,dibaca_pada')
          .or('and(dari.eq.$_me,ke.eq.$_lawan),and(dari.eq.$_lawan,ke.eq.$_me)')
          .order('created_at', ascending: false)
          .limit(200));
      if (_rows.any((r) => '${r['dari']}' == _lawan && r['dibaca_pada'] == null)) {
        await Session.db.rpc('baca_pesan', params: {'p_dari': _lawan});
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cekStatus() async {
    try {
      final s = asMap(await Session.db.rpc('status_atasan', params: {'p_id': _lawan}));
      if (mounted && s.isNotEmpty) setState(() => _status = StatusOnline.dari(s, parseWib));
    } catch (_) {}
  }

  Future<void> _hapusPercakapan() async {
    final ok = await confirmDialog(
      context,
      'Hapus percakapan ini?',
      'Semua pesan antara kamu dan ${widget.kontak['nama']} dihapus permanen untuk kalian berdua.',
      yes: 'Hapus',
    );
    if (!ok) return;
    try {
      await Session.db.rpc('hapus_percakapan', params: {'p_lawan': _lawan});
      await _load();
      if (mounted) showMsg(context, 'Percakapan dihapus');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _send() async {
    final t = _isi.text.trim();
    if (t.isEmpty) return;
    setState(() => _kirim = true);
    try {
      await Session.db.rpc('kirim_pesan', params: {'p_ke': _lawan, 'p_isi': t});
      _isi.clear();
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _kirim = false);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kontak;
    final c = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          AvatarProfil(url: k['foto_url'] as String?, nama: '${k['nama']}', radius: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${k['nama']}'),
            Text('${(k['jabatan'] as String? ?? _peran(k['role'] as String?))}${k['area'] != null ? ' · ${k['area']}' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              LampuOnline(online: _status.online, size: 9),
              const SizedBox(width: 4),
              Flexible(
                child: Text(teksStatus(_status),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
              ),
            ]),
          ])),
        ]),
        actions: [
          if (Session.current?.isPic ?? false)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'hapus') _hapusPercakapan();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'hapus',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                    title: Text('Hapus percakapan ini', style: TextStyle(color: Colors.red.shade700)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState(icon: Icons.chat_bubble_outline, text: 'Belum ada pesan. Mulai percakapan di bawah.')
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final saya = '${r['dari']}' == _me;
                        final w = parseWib('${r['created_at']}');
                        final sebelumnya = i + 1 < _rows.length ? parseWib('${_rows[i + 1]['created_at']}') : null;
                        final hariBaru = sebelumnya == null || !isSameDay(dateOnly(w), dateOnly(sebelumnya));
                        return Column(children: [
                          if (hariBaru)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(hariTgl(dateOnly(w)), style: Theme.of(context).textTheme.bodySmall),
                            ),
                          Align(
                            alignment: saya ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                              decoration: BoxDecoration(
                                color: saya ? c.withValues(alpha: 0.14) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                SelectableText('${r['isi']}', style: const TextStyle(fontSize: 14.5)),
                                const SizedBox(height: 2),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(jamMenit(w), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                                  if (saya) ...[
                                    const SizedBox(width: 4),
                                    Icon(r['dibaca_pada'] != null ? Icons.done_all : Icons.done,
                                        size: 14, color: r['dibaca_pada'] != null ? Colors.blue : Colors.grey),
                                  ],
                                ]),
                              ]),
                            ),
                          ),
                        ]);
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _isi,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Tulis pesan...', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _kirim ? null : _send, icon: busyIcon(_kirim, Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
