import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils.dart';
import 'widgets.dart';

/// Bottom sheet daftar dengan kolom pencarian.
Future<Map<String, dynamic>?> showSearchPicker(
  BuildContext context, {
  required String title,
  required Future<List<Map<String, dynamic>>> Function() loader,
  required String Function(Map<String, dynamic>) titleOf,
  String Function(Map<String, dynamic>)? subtitleOf,
  String Function(Map<String, dynamic>)? trailingOf,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SearchSheet(
      title: title,
      loader: loader,
      titleOf: titleOf,
      subtitleOf: subtitleOf,
      trailingOf: trailingOf,
    ),
  );
}

class _SearchSheet extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final String Function(Map<String, dynamic>) titleOf;
  final String Function(Map<String, dynamic>)? subtitleOf;
  final String Function(Map<String, dynamic>)? trailingOf;

  const _SearchSheet({
    required this.title,
    required this.loader,
    required this.titleOf,
    this.subtitleOf,
    this.trailingOf,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _all = await widget.loader();
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = _all.where((m) {
      if (q.isEmpty) return true;
      final s = '${widget.titleOf(m)} ${widget.subtitleOf?.call(m) ?? ''}'.toLowerCase();
      return s.contains(q);
    }).toList();
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari...', isDense: true),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : items.isEmpty
                        ? const Center(child: Text('Tidak ada data'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final m = items[i];
                              final sub = widget.subtitleOf?.call(m);
                              final tr = widget.trailingOf?.call(m);
                              return ListTile(
                                title: Text(widget.titleOf(m)),
                                subtitle: sub == null ? null : Text(sub),
                                trailing: tr == null ? null : Text(tr),
                                onTap: () => Navigator.pop(context, m),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

/// Pilih produk dari master (tipe 'HP' / 'IOT', atau null = semua).
Future<Map<String, dynamic>?> showProductPicker(BuildContext context, {String? tipe}) {
  return showSearchPicker(
    context,
    title: tipe == null ? 'Pilih produk' : (tipe == 'HP' ? 'Pilih produk HP' : 'Pilih produk IoT'),
    loader: () async {
      var q = Session.db.from('products').select().eq('aktif', true);
      if (tipe != null) q = q.eq('tipe', tipe);
      final rows = await q.order('tipe').order('grup').order('harga', ascending: false);
      return asList(rows);
    },
    titleOf: (m) => '${m['nama']}',
    subtitleOf: (m) => '${m['grup']}',
    trailingOf: (m) => rupiah(toNum(m['harga'])),
  );
}

/// Pilih konsumen dari database milik PC.
Future<Map<String, dynamic>?> showContactPicker(BuildContext context, String pcId) {
  return showSearchPicker(
    context,
    title: 'Pilih konsumen',
    loader: () async {
      final rows = await Session.db
          .from('contacts')
          .select('id,nama,no_hp,kategori,status')
          .eq('pc_id', pcId)
          .order('created_at', ascending: false);
      return asList(rows);
    },
    titleOf: (m) => '${m['nama']}',
    subtitleOf: (m) => '${m['no_hp']} · ${m['kategori']}',
    trailingOf: (m) => '${m['status']}',
  );
}
