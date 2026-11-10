import '../services/session.dart';
import '../utils.dart';

Future<Map<String, num>> loadTargets(String pcId, DateTime bulan) async {
  final rows = await Session.db
      .from('targets')
      .select('jenis,nilai')
      .eq('pc_id', pcId)
      .eq('bulan', ymd(monthStart(bulan)));
  return {for (final r in rows) r['jenis'] as String: toNum(r['nilai'])};
}
