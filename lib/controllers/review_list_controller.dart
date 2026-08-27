import 'package:customer/constant/collection_name.dart';
import 'package:customer/models/product_model.dart';
import 'package:customer/models/rating_model.dart';
import 'package:customer/models/review_attribute_model.dart';
import 'package:customer/models/vendor_model.dart';
import 'package:customer/utils/fire_store_utils.dart';
import 'package:get/get.dart';

class ReviewListController extends GetxController {
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getArgument();
    super.onInit();
  }

  Rx<VendorModel> vendorModel = VendorModel().obs;
  RxList<RatingModel> ratingList = <RatingModel>[].obs;

  // Nom du produit noté ("Rate for - X") et titres des attributs d'avis,
  // préchargés une fois par id unique au lieu d'un FutureBuilder qui refetch
  // à chaque rebuild de la liste.
  RxMap<String, String> productNameCache = <String, String>{}.obs;
  RxMap<String, String> reviewAttributeTitleCache = <String, String>{}.obs;

  getArgument() {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      vendorModel.value = argumentData['vendorModel'];
      getAllReview();
    }
    isLoading.value = false;
  }

  getAllReview() async {
    await FireStoreUtils.getVendorReviews(vendorModel.value.id.toString()).then(
      (value) {
        ratingList.value = value;
      },
    );
    await _loadCaches();
    update();
  }

  Future<void> _loadCaches() async {
    final Set<String> productIds = ratingList.where((r) => r.productId != null).map((r) => r.productId!.split('~').first).toSet();
    final Set<String> attributeKeys = ratingList.where((r) => r.reviewAttributes != null).expand((r) => r.reviewAttributes!.keys).toSet();

    await Future.wait([
      ...productIds.map((id) async {
        final doc = await FireStoreUtils.fireStore.collection(CollectionName.vendorProducts).doc(id).get();
        if (doc.exists) {
          productNameCache[id] = ProductModel.fromJson(doc.data()!).name ?? '';
        }
      }),
      ...attributeKeys.map((key) async {
        final doc = await FireStoreUtils.fireStore.collection(CollectionName.reviewAttributes).doc(key).get();
        if (doc.exists) {
          reviewAttributeTitleCache[key] = ReviewAttributeModel.fromJson(doc.data()!).title ?? '';
        }
      }),
    ]);
  }
}
