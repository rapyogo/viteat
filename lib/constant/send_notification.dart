import 'package:customer/services/server_api.dart';

/// Façade des notifications push.
///
/// Les push FCM sont désormais envoyés par le serveur via la callable
/// `v1_sendPush` : l'application ne télécharge plus la clé du compte de
/// service (`serviceJson`) et ne contacte plus directement l'API FCM. Le
/// titre et le corps sont construits côté serveur à partir du type, de la
/// commande / réservation et des modèles de notification.
class SendNotification {
  SendNotification._();

  /// Nouvelle commande (client → restaurant) ; `scheduled` pour une commande
  /// programmée.
  static Future<bool> orderPlaced({required String orderId, bool scheduled = false}) {
    return ServerApi.sendPush(type: scheduled ? 'schedule_order' : 'order_placed', orderId: orderId);
  }

  /// Annulation d'une commande par le client (client → restaurant).
  static Future<bool> customerCancelled({required String orderId}) {
    return ServerApi.sendPush(type: 'customer_cancelled', orderId: orderId);
  }

  /// Nouvelle réservation dine-in (client → restaurant).
  static Future<bool> dineInPlaced({required String bookingId}) {
    return ServerApi.sendPush(type: 'dinein_placed', bookingId: bookingId);
  }

  /// Message de chat : `targetUserId` = uid du destinataire ou id du
  /// restaurant ; message tronqué à 500 caractères.
  static Future<bool> chat({required String targetUserId, required String message, String? chatType, String? orderId}) {
    return ServerApi.sendPush(type: 'chat', targetUserId: targetUserId, message: message, chatType: chatType, orderId: orderId);
  }
}
