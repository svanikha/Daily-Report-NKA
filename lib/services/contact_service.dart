import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

/// Membuka WhatsApp, WhatsApp Business, atau telepon ke nomor konsumen.
class ContactService {
  static const waPackage = 'com.whatsapp';
  static const waBusinessPackage = 'com.whatsapp.w4b';

  static AndroidIntent _waIntent(String no, String package) => AndroidIntent(
        action: 'action_view',
        data: 'https://wa.me/$no',
        package: package,
      );

  static Future<bool> isInstalled(String package) async {
    try {
      return await _waIntent('62', package).canResolveActivity() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openWhatsApp(String no, {bool business = false}) async {
    final intent = _waIntent(no, business ? waBusinessPackage : waPackage);
    try {
      final can = await intent.canResolveActivity() ?? false;
      if (!can) return false;
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> call(String no) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: '+$no'));
    } catch (_) {
      return false;
    }
  }
}
