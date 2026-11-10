import 'session.dart';
import 'notif_service.dart';
import '../utils.dart';

/// Menyegarkan jadwal notifikasi PC berdasarkan data terbaru di server.
class PcSync {
  static Future<void> refresh() async {
    final pc = Session.current;
    if (pc == null || pc.usesAdminHome) return;
    try {
      final db = Session.db;
      final today = todayStr();
      final res = await Future.wait<dynamic>([
        db.from('contacts').select('id,nama,kategori,created_at,last_contacted_at').eq('pc_id', pc.id),
        db.from('sales').select('id').eq('pc_id', pc.id).eq('tanggal', today).limit(1),
        db.from('social_activities').select('id').eq('pc_id', pc.id).eq('tanggal', today).limit(1),
        db.from('leasing_checks').select('id').eq('pc_id', pc.id).eq('tanggal', today).limit(1),
        db.from('checkins').select('modul').eq('pc_id', pc.id).eq('tanggal', today),
        db.from('pc_day_status').select('tanggal').eq('pc_id', pc.id).gte('tanggal', today).lte('tanggal', ymd(addDays(wibToday(), 45))),
        db.from('breaks').select('mulai,selesai,durasi_menit').eq('pc_id', pc.id).eq('tanggal', today),
      ]);
      final checkins = asList(res[4]);
      final reportDone = asList(res[1]).isNotEmpty || checkins.any((c) => c['modul'] == 'report');
      final activityDone = asList(res[2]).isNotEmpty ||
          asList(res[3]).isNotEmpty ||
          checkins.any((c) => c['modul'] == 'activity');
      final offdays = asList(res[5]).map((r) => '${r['tanggal']}').toSet();
      final brk = asList(res[6]);
      final active = brk.isNotEmpty && brk.first['selesai'] == null;
      await NotifService.reschedule(
        contacts: asList(res[0]),
        todayDone: reportDone && activityDone,
        offdays: offdays,
        breakStart: active ? parseWib(brk.first['mulai'] as String) : null,
        breakMenit: active ? toNum(brk.first['durasi_menit'] ?? 180).toInt() : 180,
      );
    } catch (_) {
      // Tidak fatal: notifikasi akan dijadwalkan ulang saat aplikasi dibuka lagi.
    }
  }
}
