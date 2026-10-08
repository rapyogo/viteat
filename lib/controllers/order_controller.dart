import 'package:customer/app/cart_screen/cart_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/models/cart_product_model.dart';
import 'package:customer/models/order_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/services/cart_provider.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class OrderController extends GetxController {
  RxList<OrderModel> allList = <OrderModel>[].obs;
  RxList<OrderModel> inProgressList = <OrderModel>[].obs;
  RxList<OrderModel> deliveredList = <OrderModel>[].obs;
  RxList<OrderModel> rejectedList = <OrderModel>[].obs;
  RxList<OrderModel> cancelledList = <OrderModel>[].obs;

  // Statut d'abonnement vendeur en direct pour le bouton "Reorder" (pas le
  // vendor embarqué dans la commande, potentiellement perime) — precharge une
  // fois par vendeur unique au lieu d'un FutureBuilder qui refetch a chaque
  // rebuild de la liste.
  RxMap<String, VendorModel> vendorCache = <String, VendorModel>{}.obs;

  RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    getOrder();
  }

  DateTime? _lastLoaded;

  /// Rafraichissement silencieux si les donnees ont plus de [maxAge].
  Future<void> refreshIfStale(Duration maxAge) async {
    if (_lastLoaded != null && DateTime.now().difference(_lastLoaded!) < maxAge) return;
    await getOrder(silent: true);
  }

  Future<void> getOrder({bool silent = false}) async {
    _lastLoaded = DateTime.now();
    // La session Firebase fait foi : au demarrage hors ligne, le profil peut
    // manquer alors que la session est valide, et la liste restait vide.
    if (FirebaseAuth.instance.currentUser != null) {
      await FireStoreUtils.getAllOrder().then((value) {
        if (!silent) isLoading.value = true;
        allList.value = value;

        rejectedList.value = allList.where((p0) => p0.status == Constant.orderRejected).toList();
        inProgressList.value =
            allList.where((p0) => p0.status == Constant.orderAccepted || p0.status == Constant.driverPending || p0.status == Constant.orderShipped || p0.status == Constant.orderInTransit).toList();

        deliveredList.value = allList.where((p0) => p0.status == Constant.orderCompleted).toList();
        cancelledList.value = allList.where((p0) => p0.status == Constant.orderCancelled).toList();
      });
      await _loadVendorCache();
    }

    isLoading.value = false;
  }

  Future<void> _loadVendorCache() async {
    final List<String> vendorIds = allList.map((o) => o.vendorID).whereType<String>().toSet().where((id) => !vendorCache.containsKey(id)).toList();
    if (vendorIds.isEmpty) return;
    final List<VendorModel?> results = await Future.wait(vendorIds.map((id) => FireStoreUtils.getVendorById(id)));
    for (int i = 0; i < vendorIds.length; i++) {
      final VendorModel? vendor = results[i];
      if (vendor != null) vendorCache[vendorIds[i]] = vendor;
    }
  }

  final CartProvider cartProvider = CartProvider();

  void addToCart({required CartProductModel cartProductModel}) {
    cartProvider.addToCart(Get.context!, cartProductModel, cartProductModel.quantity!);
    update();
  }

  /// Vrai si AU MOINS UN produit de la commande est encore disponible (Foodie 9.2).
  /// Avant, un seul article retire masquait « Recommander » sur toute la commande.
  /// L'identifiant panier d'un produit a variante est `produitId~varianteId`.
  Future<bool> hasAnyPublishedProduct(List<CartProductModel>? products) async {
    if (products == null || products.isEmpty) return false;
    // Un getProductById() par article, lancés en parallèle plutôt qu'en séquence.
    final results = await Future.wait(products.map((item) => FireStoreUtils.getProductById(item.id?.split('~').first ?? '')));
    return results.any((product) => product != null && product.publish != false);
  }

  /// Remet au panier les produits encore disponibles d'une commande, puis ouvre
  /// le panier (Foodie 9.2). Les articles supprimés ou dépubliés sont ignorés et
  /// signalés, au lieu d'un toast par article.
  Future<void> reorder(OrderModel orderModel) async {
    final List<CartProductModel> items = orderModel.products ?? [];
    if (items.isEmpty) return;
    ShowToastDialog.showLoader("Please wait");
    int skipped = 0;
    final List<CartProductModel> available = [];
    try {
      final results = await Future.wait(items.map((item) => FireStoreUtils.getProductById(item.id?.split('~').first ?? '')));
      for (int i = 0; i < items.length; i++) {
        final product = results[i];
        if (product == null || product.publish == false) {
          skipped++;
        } else {
          available.add(items[i]);
        }
      }
    } finally {
      ShowToastDialog.closeLoader();
    }

    if (available.isEmpty) {
      ShowToastDialog.showToast("These items are no longer available.");
      return;
    }
    for (final item in available) {
      cartProvider.addToCart(Get.context!, item, item.quantity ?? 1);
    }
    update();
    ShowToastDialog.showToast(skipped > 0 ? "Some items are no longer available and were not added." : "Items added to your cart");
    await Get.to(const CartScreen());
  }
}
