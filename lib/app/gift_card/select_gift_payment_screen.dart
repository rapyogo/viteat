import 'package:customer/app/wallet_screen/wallet_screen.dart';
import 'package:customer/constant/constant.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/controllers/gift_card_controller.dart';
import 'package:customer/controllers/phonepay_controller.dart';
import 'package:customer/payment/createRazorPayOrderModel.dart';
import 'package:customer/payment/rozorpayConroller.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

class SelectGiftPaymentScreen extends StatelessWidget {
  const SelectGiftPaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    return GetX(
      init: GiftCardController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: themeChange.getThem() ? AppThemeData.surfaceDark : AppThemeData.surface,
          appBar: AppBar(
            backgroundColor: themeChange.getThem() ? AppThemeData.surfaceDark : AppThemeData.surface,
            centerTitle: false,
            titleSpacing: 0,
            title: TranslatedText(
              "Payment Option",
              textAlign: TextAlign.start,
              style: TextStyle(
                fontFamily: AppThemeData.medium,
                fontSize: 16,
                color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
          ),
          body: controller.isLoadingPayment.value == true
              ? Align(
                  alignment: Alignment.center,
                  child: TranslatedText(
                    "Loading, please wait...",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppThemeData.semiBold,
                      fontSize: 16,
                      color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TranslatedText(
                          "Preferred Payment",
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontFamily: AppThemeData.semiBold,
                            fontSize: 16,
                            color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        if (controller.walletSettingModel.value.isEnabled == true)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: ShapeDecoration(
                                  color: themeChange.getThem() ? AppThemeData.grey900 : AppThemeData.grey50,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  shadows: const [
                                    BoxShadow(
                                      color: Color(0x07000000),
                                      blurRadius: 20,
                                      offset: Offset(0, 0),
                                      spreadRadius: 0,
                                    )
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    children: [
                                      Visibility(
                                        visible: Constant.isServerVerifiedGateway(PaymentGateway.wallet.name) && controller.walletSettingModel.value.isEnabled == true,
                                        child: cardDecoration(controller, PaymentGateway.wallet, themeChange, "assets/images/ic_wallet.png"),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                              TranslatedText(
                                "Other Payment Options",
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  fontFamily: AppThemeData.semiBold,
                                  fontSize: 16,
                                  color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                                ),
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                            ],
                          ),
                        Container(
                          decoration: ShapeDecoration(
                            color: themeChange.getThem() ? AppThemeData.grey900 : AppThemeData.grey50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            shadows: const [
                              BoxShadow(
                                color: Color(0x07000000),
                                blurRadius: 20,
                                offset: Offset(0, 0),
                                spreadRadius: 0,
                              )
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Visibility(
                                  visible: Constant.isServerVerifiedGateway(PaymentGateway.flexPay.name) && controller.flexPayModel.value.enable == true,
                                  child: cardDecoration(controller, PaymentGateway.flexPay, themeChange, "assets/images/mtnmom.png"),
                                ),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
                color: themeChange.getThem() ? AppThemeData.grey900 : AppThemeData.grey50, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: RoundedButtonFill(
                title: "Pay Now",
                height: 5,
                color: AppThemeData.primary300,
                textColor: AppThemeData.grey50,
                fontSizes: 16,
                onPress: () async {
                  // Achat de carte cadeau : seuls le portefeuille et FlexPay
                  // sont supportés par le serveur (v1_walletBuyGiftCard).
                  if (!controller.isSupportedGiftPaymentMethod) {
                    ShowToastDialog.showToast("Gift cards can only be purchased with your wallet or Mobile Money.");
                    return;
                  }
                  if (controller.selectedPaymentMethod.value == PaymentGateway.flexPay.name) {
                    controller.flexPayMakePayment(amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.stripe.name) {
                    controller.stripeMakePayment(amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.paypal.name) {
                    controller.paypalPaymentSheet(controller.amountController.value.text, context);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.payStack.name) {
                    controller.payStackPayment(controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.mercadoPago.name) {
                    controller.mercadoPagoMakePayment(context: context, amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.flutterWave.name) {
                    controller.flutterWaveInitiatePayment(context: context, amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.payFast.name) {
                    controller.payFastPayment(context: context, amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.paytm.name) {
                    controller.getPaytmCheckSum(context, amount: double.parse(controller.amountController.value.text));
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.midTrans.name) {
                    controller.midtransMakePayment(context: context, amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.orangeMoney.name) {
                    controller.orangeMakePayment(context: context, amount: controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.xendit.name) {
                    controller.xenditPayment(context, controller.amountController.value.text);
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.mtnMomo.name.toLowerCase()) {
                    await controller.mtnMomoMakePayment(amount: controller.amountController.value.text.toString());
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.phonePe.name.toLowerCase()) {
                    PhonePePaymentService.phonePe = controller.phonePeModel.value;
                    await PhonePePaymentService.payNow(amountInPaise: (double.parse(controller.amountController.value.text.toString()) * 100).round());
                    if (PhonePePaymentService.isSucess) {
                      controller.placeOrder();
                    }
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.cashfree.name.toLowerCase()) {
                    controller.cashFreeMakePayment(context: context, amount: controller.amountController.value.text.toString(), paymentDesc: "GiftCard Payment");
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.instamojo.name.toLowerCase()) {
                    controller.makeInstamojoPayment(amount: controller.amountController.value.text.toString(), paymentDesc: "GiftCard Payment");
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.foloosi.name.toLowerCase()) {
                    controller.makeFoloosiPayment(amount: controller.amountController.value.text.toString(), paymentDesc: "GiftCard Payment");
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.payMongo.name.toLowerCase()) {
                    controller.makePayMongoPayment(amount: controller.amountController.value.text.toString(), paymentDesc: "GiftCard Payment");
                  } else if (controller.selectedPaymentMethod.value.toLowerCase() == PaymentGateway.wallet.name) {
                    controller.placeOrder();
                  } else if (controller.selectedPaymentMethod.value == PaymentGateway.razorpay.name) {
                    ShowToastDialog.showLoader("Please wait");
                    RazorPayController().createOrderRazorPay(amount: double.parse(controller.amountController.value.text), razorpayModel: controller.razorPayModel.value).then((value) {
                      if (value == null) {
                        ShowToastDialog.showToast("Something went wrong, please contact admin.");
                      } else {
                        CreateRazorPayOrderModel result = value;
                        controller.openCheckout(amount: controller.amountController.value.text, orderId: result.id);
                      }
                    });
                  } else {
                    ShowToastDialog.showToast("Please select payment method");
                    ShowToastDialog.closeLoader();
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  cardDecoration(GiftCardController controller, PaymentGateway value, themeChange, String image) {
    return Obx(
      () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          onTap: () {
            controller.selectedPaymentMethod.value = value.name;
          },
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(value.name == "payFast" ? 0 : 8.0),
                  child: Image.asset(
                    image,
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              value.name == "wallet"
                  ? Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TranslatedText(
                            value.name.capitalizeString(),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: AppThemeData.medium,
                              fontSize: 16,
                              color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                            ),
                          ),
                          Text(
                            Constant.amountShow(amount: controller.userModel.value.walletAmount == null ? '0.0' : controller.userModel.value.walletAmount.toString()),
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: AppThemeData.semiBold,
                              fontSize: 16,
                              color: themeChange.getThem() ? AppThemeData.primary300 : AppThemeData.primary300,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Expanded(
                      child: TranslatedText(
                        value.name.capitalizeString(),
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontFamily: AppThemeData.medium,
                          fontSize: 16,
                          color: themeChange.getThem() ? AppThemeData.grey50 : AppThemeData.grey900,
                        ),
                      ),
                    ),
              const Expanded(
                child: SizedBox(),
              ),
              Radio(
                value: value.name,
                groupValue: controller.selectedPaymentMethod.value,
                activeColor: themeChange.getThem() ? AppThemeData.primary300 : AppThemeData.primary300,
                onChanged: (value) {
                  controller.selectedPaymentMethod.value = value.toString();
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
