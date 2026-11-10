import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../services/contact_service.dart';
import '../../services/pc_sync.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import 'contact_form.dart';

class ContactDetail extends StatefulWidget {
  final Profile pc;
  final String contactId;
  final bool adminView;
  const ContactDetail({super.key, required this.pc, required this.contactId, this.adminView = false});

  @override
  State<ContactDetail> createState() => _ContactDetailState();
}

class _ContactDetailState extends State<ContactDetail> with WidgetsBindingObserver {
  Map<String, dynamic>? _c;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  String? _pendingChannel;
  bool _hasWa = true;
  bool _hasWaBiz = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingChannel != null) {
      final ch = _pendingChannel!;
      _pendingChannel = null;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _askContacted(ch);
      });
    }
  }

  Future<void> _checkApps() async {
    final wa = await ContactService.isInstalled(ContactService.waPackage);
    final biz = await ContactService.isInstalled(ContactService.waBusinessPackage);
    if (mounted) {
      setState(() {
        _hasWa = wa;
        _hasWaBiz = biz;
      });
    }
  }

  Future<void> _load() async {
    try {
      final db = Session.db;
      final c = await db.from('contacts').select().eq('id', widget.contactId).single();
      final logs = await db.from('contact_logs').select().eq('contact_id', widget.contactId).order('waktu', ascending: false);
      _c = c;
      _logs = asList(logs);
      _error = null;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _contact(String channel) async {
    final no = '${_c!['no_hp']}';
    bool ok;
    if (channel == 'telepon') {
      ok = await ContactService.call(no);
    } else {
      ok = await ContactService.openWhatsApp(no, business: channel == 'wa_bisnis');
    }
    if (!mounted) return;
    if (!ok) {
      showMsg(context, channel == 'telepon' ? 'Tidak bisa membuka telepon' : 'Aplikasi WhatsApp tidak ditemukan di HP ini');
      return;
    }
    _pendingChannel = channel;
  }

  Future<void> _askContacted(String channel) async {
    final c = _c;
    if (c == null) return;
    final hasil = TextEditingController();
    String status = '${c['status']}';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Sudah menghubungi ${c['nama']}?'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: hasil,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Hasil singkat (opsional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status konsumen'),
                items: [for (final s in statusUser) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => setD(() => status = v ?? status),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Belum')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, sudah')),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      final h = hasil.text.trim();
      await Session.db.from('contact_logs').insert({
        'contact_id': widget.contactId,
        'pc_id': widget.pc.id,
        'channel': channel,
        'dihubungi': result,
        'hasil': h.isEmpty ? null : h,
        'status_baru': status != c['status'] ? status : null,
      });
      await _load();
      PcSync.refresh();
      if (mounted && result) showMsg(context, 'Kontak tercatat');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _changeStatus() async {
    final c = _c;
    if (c == null) return;
    final s = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ubah status'),
        children: [
          for (final s in statusUser)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Row(children: [
                StatusChip(s),
                const SizedBox(width: 8),
                Expanded(child: Text(statusDesc[s] ?? '')),
              ]),
            ),
        ],
      ),
    );
    if (s == null || s == c['status']) return;
    try {
      await Session.db.from('contact_logs').insert({
        'contact_id': widget.contactId,
        'pc_id': widget.pc.id,
        'channel': 'status',
        'dihubungi': false,
        'status_baru': s,
      });
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ContactForm(pc: widget.pc, existing: _c),
    ));
    if (ok == true) _load();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'Hapus kontak?', 'Kontak dan riwayatnya akan dihapus permanen.', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('contacts').delete().eq('id', widget.contactId);
      PcSync.refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Detail kontak' : '${c['nama']}'),
        actions: [
          if (c != null && !widget.adminView) IconButton(onPressed: _edit, icon: const Icon(Icons.edit), tooltip: 'Edit'),
          if (c != null && (!widget.adminView || adminCanEdit(widget.adminView))) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Hapus'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null || c == null)
              ? ErrorRetry(error: _error ?? 'Kontak tidak ditemukan', onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body(c)),
    );
  }

  Widget _body(Map<String, dynamic> c) {
    final today = wibToday();
    final ms = monthStart();
    final monthLogs = _logs.where((l) => l['dihubungi'] == true && !parseWib(l['waktu'] as String).isBefore(ms)).length;
    final lastRaw = c['last_contacted_at'];
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${c['nama']}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              StatusChip('${c['status']}'),
            ]),
            const SizedBox(height: 4),
            Text('+${c['no_hp']}', style: t.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              Pill('${c['kategori']}', color: Colors.indigo),
              if (c['produk_minat'] != null) Pill('Minat: ${c['produk_minat']}', color: Colors.teal),
            ]),
            if ((c['catatan'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${c['catatan']}'),
            ],
            const SizedBox(height: 8),
            Text('Diinput: ${tglJam(parseWib(c['created_at'] as String))}', style: t.bodySmall),
            if (!widget.adminView)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: _changeStatus, icon: const Icon(Icons.swap_horiz), label: const Text('Ubah status')),
              ),
          ]),
        ),
      ),
      if (!widget.adminView) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _contact('telepon'),
              icon: const Icon(Icons.call),
              label: const Text('Telepon'),
            ),
          ),
          if (_hasWa) ...[
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _contact('whatsapp'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp'),
              ),
            ),
          ],
          if (_hasWaBiz) ...[
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _contact('wa_bisnis'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
                icon: const Icon(Icons.business_center),
                label: const Text('WA Bisnis'),
              ),
            ),
          ],
        ]),
      ],
      const SizedBox(height: 8),
      StatGrid(children: [
        StatCard(icon: Icons.repeat, label: 'Dihubungi bulan ini', value: '$monthLogs kali'),
        StatCard(
          icon: Icons.schedule,
          label: 'Terakhir dihubungi',
          value: lastRaw == null ? '-' : tgl(parseWib(lastRaw as String)),
        ),
      ]),
      const SectionHeader('Jadwal follow up'),
      Card(
        child: Column(children: [
          for (final r in remindersOf(c))
            ListTile(
              dense: true,
              leading: Icon(_reminderIcon(r.status(today)), color: _reminderColor(r.status(today))),
              title: Text('H+${r.h} · ${tglPendek(r.due)}'),
              trailing: Text(r.status(today), style: TextStyle(color: _reminderColor(r.status(today)), fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      const SectionHeader('Riwayat'),
      if (_logs.isEmpty) const EmptyState(icon: Icons.history, text: 'Belum ada riwayat kontak'),
      for (final l in _logs)
        Card(
          child: ListTile(
            leading: Icon(_channelIcon('${l['channel']}'), color: l['dihubungi'] == true ? Colors.green : Colors.grey),
            title: Text(_logTitle(l)),
            subtitle: Text([
              if ((l['hasil'] ?? '').toString().isNotEmpty) '${l['hasil']}',
              tglJam(parseWib(l['waktu'] as String)),
            ].join('\n')),
          ),
        ),
      const SizedBox(height: 24),
    ]);
  }

  String _logTitle(Map<String, dynamic> l) {
    final ch = '${l['channel']}';
    if (ch == 'status' && l['hasil'] == 'Status awal') return 'Status awal: ${l['status_baru']}';
    if (ch == 'status') return 'Status diubah ke ${l['status_baru']}';
    final base = '${channelLabel[ch] ?? ch} · ${l['dihubungi'] == true ? 'Terhubung' : 'Belum terhubung'}';
    return l['status_baru'] != null ? '$base · status ${l['status_baru']}' : base;
  }

  IconData _channelIcon(String ch) {
    switch (ch) {
      case 'telepon':
        return Icons.call;
      case 'whatsapp':
        return Icons.chat;
      case 'wa_bisnis':
        return Icons.business_center;
      default:
        return Icons.swap_horiz;
    }
  }

  IconData _reminderIcon(String s) {
    switch (s) {
      case 'Selesai':
        return Icons.check_circle;
      case 'Terlewat':
        return Icons.error;
      case 'Hari ini':
        return Icons.notifications_active;
      default:
        return Icons.schedule;
    }
  }

  Color _reminderColor(String s) {
    switch (s) {
      case 'Selesai':
        return Colors.green;
      case 'Terlewat':
        return Colors.red;
      case 'Hari ini':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }
}
