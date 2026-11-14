import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
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

  @override
  void initState() {
    super.initState();
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
    final c = _ch;
    if (c != null) Session.db.removeChannel(c);
    super.dispose();
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
        .where((k) => q.isEmpty || '${k['nama']} ${_peran(k['role'] as String?)} ${k['area'] ?? ''}'.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Pesan')),
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
        leading: CircleAvatar(child: Text(nama.isEmpty ? '?' : nama[0].toUpperCase())),
        title: Text(nama, style: TextStyle(fontWeight: belum > 0 ? FontWeight.bold : FontWeight.w600)),
        subtitle: Text(
          k['terakhir'] != null
              ? '${k['terakhir']}'
              : '${_peran(k['role'] as String?)}${k['area'] != null ? ' · ${k['area']}' : ''}',
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

  String get _lawan => '${widget.kontak['id']}';
  String get _me => Session.current!.id;

  @override
  void initState() {
    super.initState();
    _load();
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${k['nama']}'),
          Text('${_peran(k['role'] as String?)}${k['area'] != null ? ' · ${k['area']}' : ''}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
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
