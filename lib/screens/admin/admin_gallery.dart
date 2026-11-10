import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';

/// Galeri bukti foto (screenshot sosmed dan selfie leasing) untuk admin.
class AdminGallery extends StatefulWidget {
  final DateTime dari;
  final DateTime sampai;
  final Map<String, String> pcNames;
  const AdminGallery({super.key, required this.dari, required this.sampai, required this.pcNames});

  @override
  State<AdminGallery> createState() => _AdminGalleryState();
}

class _AdminGalleryState extends State<AdminGallery> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _photos = [];
  final Map<String, String> _urls = {};
  String _filter = 'semua';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _utcIso(DateTime wibDate) =>
      DateTime.utc(wibDate.year, wibDate.month, wibDate.day).subtract(const Duration(hours: 7)).toIso8601String();

  Future<void> _load() async {
    try {
      final ids = widget.pcNames.keys.toList();
      if (ids.isEmpty) {
        _photos = [];
      } else {
        final rows = await Session.db
            .from('photos')
            .select()
            .inFilter('pc_id', ids)
            .gte('created_at', _utcIso(widget.dari))
            .lt('created_at', _utcIso(addDays(widget.sampai, 1)))
            .order('created_at', ascending: false)
            .limit(300);
        _photos = asList(rows);
        final storage = Session.db.storage.from('bukti');
        for (var i = 0; i < _photos.length; i += 50) {
          final chunk = _photos.skip(i).take(50).map((p) => p['path'] as String).toList();
          final signed = await storage.createSignedUrls(chunk, 3600);
          for (final s in signed) {
            _urls[s.path] = s.signedUrl;
          }
        }
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _photos.where((p) {
      if (_filter == 'semua') return true;
      if (_filter == 'bertanda') return p['flags'] is List && (p['flags'] as List).isNotEmpty;
      return p['ref_tabel'] == _filter;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Galeri bukti foto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(
                  error: _error!,
                  onRetry: () {
                    setState(() => _loading = true);
                    _load();
                  },
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final f in const [
                          ['semua', 'Semua'],
                          ['social_activities', 'Sosmed'],
                          ['leasing_checks', 'Leasing'],
                          ['store_checklists', 'Checklist'],
                          ['bertanda', 'Bertanda'],
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(f[1]),
                              selected: _filter == f[0],
                              onSelected: (_) => setState(() => _filter = f[0]),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.photo, text: 'Belum ada foto pada periode ini')
                        : GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final p = list[i];
                              final url = _urls[p['path']];
                              return InkWell(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PhotoViewerPage(photos: [p], title: widget.pcNames[p['pc_id']] ?? 'Foto'),
                                )),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(
                                    child: Stack(children: [
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: url == null
                                              ? Container(color: Colors.grey.shade300)
                                              : Image.network(url, fit: BoxFit.cover, width: double.infinity, cacheWidth: 300),
                                        ),
                                      ),
                                      if (p['flags'] is List && (p['flags'] as List).isNotEmpty)
                                        const Positioned(
                                          right: 4,
                                          top: 4,
                                          child: Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
                                        ),
                                    ]),
                                  ),
                                  Text(
                                    widget.pcNames[p['pc_id']] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${const {'leasing_checks': 'Leasing', 'store_checklists': 'Checklist'}[p['ref_tabel']] ?? 'Sosmed'} · ${p['sumber']} · ${tglPendek(parseWib(p['created_at'] as String))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}
