import 'package:cloud_functions/cloud_functions.dart';

class WhatsAppLinkService {
  static Future<Map<String, dynamic>> createCode() async {
    final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createWhatsAppLinkCode');
    final HttpsCallableResult<dynamic> result = await callable.call();
    return Map<String, dynamic>.from(result.data as Map);
  }
}
