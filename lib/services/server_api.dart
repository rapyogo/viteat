import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Façade des callables serveur (Functions v1 onCall, us-central1).
///
/// Toutes les opérations sensibles (portefeuille, cartes cadeaux, push FCM)
/// sont exécutées côté serveur : l'application n'écrit plus jamais dans
/// `wallet`, `gift_purchases` ni dans les champs serveur de `users`.
class ServerApi {
  ServerApi._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Identifiant d'idempotence, un par action utilisateur.
  static String newRequestId() => const Uuid().v4();

  static Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call(data);
    final raw = result.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  /// Message lisible pour une erreur de callable.
  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? error.code;
    }
    return error.toString();
  }

  // ---------------------------------------------------------------- Wallet

  static Future<Map<String, dynamic>> walletPayOrder(String orderId) => call('v1_walletPayOrder', {'orderId': orderId});

  static Future<Map<String, dynamic>> walletRefundOrder(String orderId, {String? action, String? reason}) => call('v1_walletRefundOrder', {
        'orderId': orderId,
        if (action != null) 'action': action,
        if (reason != null) 'reason': reason,
      });

  static Future<Map<String, dynamic>> walletTopUpConfirm(String reference) => call('v1_walletTopUpConfirm', {'provider': 'flexpay', 'reference': reference});

  static Future<Map<String, dynamic>> walletRedeemGiftCard({required String code, required String pin}) => call('v1_walletRedeemGiftCard', {'code': code, 'pin': pin});

  static Future<Map<String, dynamic>> walletBuyGiftCard({
    required String giftId,
    required num amount,
    String? message,
    required String paymentMethod,
    String? reference,
    required String requestId,
  }) =>
      call('v1_walletBuyGiftCard', {
        'giftId': giftId,
        'amount': amount,
        if (message != null && message.isNotEmpty) 'message': message,
        'paymentMethod': paymentMethod,
        if (reference != null) 'reference': reference,
        'requestId': requestId,
      });

  // ------------------------------------------------------------------ Push

  /// Envoi d'une notification par le serveur (titre/corps construits côté
  /// serveur). Ne lève jamais : une notification ratée ne doit pas bloquer
  /// le parcours utilisateur.
  static Future<bool> sendPush({
    required String type,
    String? orderId,
    String? bookingId,
    String? targetUserId,
    String? message,
    String? chatType,
  }) async {
    try {
      await call('v1_sendPush', {
        'type': type,
        if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
        if (bookingId != null && bookingId.isNotEmpty) 'bookingId': bookingId,
        if (targetUserId != null && targetUserId.isNotEmpty) 'targetUserId': targetUserId,
        if (message != null) 'message': message.length > 500 ? message.substring(0, 500) : message,
        if (chatType != null && chatType.isNotEmpty) 'chatType': chatType,
      });
      return true;
    } catch (e) {
      debugPrint('v1_sendPush($type) error: $e');
      return false;
    }
  }
}
