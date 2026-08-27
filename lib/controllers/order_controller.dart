import 'package:customer/constant/constant.dart';
import 'package:customer/models/cart_product_model.dart';
import 'package:customer/models/order_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/services/cart_provider.dart';
import 'package:customer/utils/fire_store_utils.dart';
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

  Future<void> getOrder() async {
    if (Constant.userModel != null) {
      await FireStoreUtils.getAllOrder().then((value) {
        isLoading.value = true;
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

  Future<bool> hasAnyPublishedProduct(List<CartProductModel>? products) async {
    if (products == null || products.isEmpty) return false;
    // Un getProductById() par article, lancés en parallèle plutôt qu'en séquence.
    final results = await Future.wait(products.map((item) => FireStoreUtils.getProductById(item.id ?? '')));
    return results.every((product) => product != null && product.publish != false);
  }
}
