import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:customer/app/terms_and_condition/terms_and_condition_screen.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/models/payment_model/flexpay_model.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

enum _FlexPayState { form, waiting, success, failed, timeout }

class FlexPayPaymentScreen extends StatefulWidget {
  final FlexPay flexPaySettings;
  final double amount;
  final String currency;

  const FlexPayPaymentScreen({super.key, required this.flexPaySettings, required this.amount, required this.currency});

  @override
  State<FlexPayPaymentScreen> createState() => _FlexPayPaymentScreenState();
}

class _FlexPayPaymentScreenState extends State<FlexPayPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  _FlexPayState _state = _FlexPayState.form;
  bool _submitting = false;
  String? _reference;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _subscription?.cancel();
    _timeoutTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  /// Traduit une erreur technique en explication comprehensible, plutot
  /// qu'un "message d'erreur" generique qui ne dit rien a l'utilisateur.
  String _friendlyErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Le service de paiement est momentanement indisponible. Veuillez réessayer dans quelques instants.';
        case 'invalid-argument':
          return 'Le numéro de téléphone saisi semble invalide. Vérifiez-le et réessayez.';
        case 'failed-precondition':
        case 'unavailable-payment-method':
          return 'Mobile Money n\'est pas disponible pour le moment. Choisissez un autre moyen de paiement.';
        default:
          return error.message ?? 'Le paiement n\'a pas pu être initié. Veuillez réessayer.';
      }
    }
    return 'Une erreur est survenue. Vérifiez votre connexion internet et réessayez.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('initiateMobileMoneyPayment');
      final result = await callable.call({
        'phone': _phoneController.text.trim(),
        'amount': widget.amount,
        'currency': widget.currency,
      });

      final reference = result.data['reference'] as String;
      _reference = reference;

      setState(() {
        _state = _FlexPayState.waiting;
        _submitting = false;
      });

      _listenForStatus(reference);
      _timeoutTimer = Timer(const Duration(minutes: 2), () {
        if (mounted && _state == _FlexPayState.waiting) {
          setState(() => _state = _FlexPayState.timeout);
        }
      });
    } catch (e) {
      setState(() => _submitting = false);
      ShowToastDialog.showToast(_friendlyErrorMessage(e));
    }
  }

  void _listenForStatus(String reference) {
    _subscription = FirebaseFirestore.instance.collection('mobile_money_payments').doc(reference).snapshots().listen((snap) {
      final status = snap.data()?['status'];
      if (status == 'completed') {
        _timeoutTimer?.cancel();
        setState(() => _state = _FlexPayState.success);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Get.back(result: true);
        });
      } else if (status == 'failed') {
        _timeoutTimer?.cancel();
        setState(() => _state = _FlexPayState.failed);
      }
    });
  }

  Future<void> _checkNow() async {
    if (_reference == null) return;
    setState(() => _submitting = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkMobileMoneyStatus');
      final result = await callable.call({'reference': _reference});
      final status = result.data['status'];
      if (status == 'completed') {
        _timeoutTimer?.cancel();
        setState(() => _state = _FlexPayState.success);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Get.back(result: true);
        });
      } else if (status == 'failed') {
        _timeoutTimer?.cancel();
        setState(() => _state = _FlexPayState.failed);
      } else {
        setState(() {
          _submitting = false;
          _state = _FlexPayState.waiting;
        });
        _timeoutTimer = Timer(const Duration(minutes: 2), () {
          if (mounted && _state == _FlexPayState.waiting) {
            setState(() => _state = _FlexPayState.timeout);
          }
        });
      }
    } catch (e) {
      setState(() => _submitting = false);
      ShowToastDialog.showToast(_friendlyErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeChange = Provider.of<DarkThemeProvider>(context);
    final bool isDark = themeChange.getThem();
    final Color textPrimary = isDark ? AppThemeData.grey50 : AppThemeData.grey900;
    final Color textSecondary = isDark ? AppThemeData.grey400 : AppThemeData.grey500;

    return Scaffold(
      backgroundColor: isDark ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
        centerTitle: false,
        titleSpacing: 0,
        leading: InkWell(
          splashColor: Colors.transparent,
          onTap: () => Get.back(result: false),
          child: Icon(Icons.chevron_left_outlined, color: textPrimary),
        ),
        title: TranslatedText(
          'Mobile Money',
          style: TextStyle(color: textPrimary, fontFamily: AppThemeData.bold, fontSize: 18),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: Container(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200, height: 4.0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Center(
                  child: Icon(Icons.phone_android_rounded, size: 64, color: AppThemeData.primary300),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TranslatedText(
                    'Viteat',
                    style: TextStyle(color: textSecondary, fontFamily: AppThemeData.medium, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 40),
                _buildBody(textPrimary, textSecondary, isDark),
                const SizedBox(height: 40),
                _buildFooter(textSecondary),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(Color textSecondary) {
    final TextStyle linkStyle = TextStyle(color: textSecondary, fontFamily: AppThemeData.medium, fontSize: 12, decoration: TextDecoration.underline);
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          InkWell(
            onTap: () => Get.to(const TermsAndConditionScreen(type: "privacy")),
            child: TranslatedText('Confidentialité', style: linkStyle),
          ),
          TranslatedText('•', style: TextStyle(color: textSecondary, fontSize: 12)),
          InkWell(
            onTap: () => Get.to(const TermsAndConditionScreen(type: "termAndCondition")),
            child: TranslatedText('Conditions d\'utilisation', style: linkStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Color textPrimary, Color textSecondary, bool isDark) {
    switch (_state) {
      case _FlexPayState.form:
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslatedText(
                'Entrez votre numéro Mobile Money'.tr,
                style: TextStyle(color: textPrimary, fontFamily: AppThemeData.medium, fontSize: 18),
              ),
              const SizedBox(height: 5),
              TranslatedText(
                'Vous recevrez une notification de paiement sur votre téléphone.'.tr,
                style: TextStyle(color: textSecondary, fontFamily: AppThemeData.regular, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  hintText: 'ex : 0812345678',
                  hintStyle: TextStyle(color: textSecondary, fontSize: 15),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: AppThemeData.primary300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ce champ est requis.'.tr;
                  }
                  if (!RegExp(r'^[0-9+\s]{8,15}$').hasMatch(value.trim())) {
                    return 'Numéro invalide.'.tr;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppThemeData.primary300, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : TranslatedText('Continuer'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      case _FlexPayState.waiting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppThemeData.primary300)),
            const SizedBox(height: 24),
            TranslatedText(
              'Une demande de paiement a été envoyée sur votre téléphone'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontFamily: AppThemeData.semiBold, color: textPrimary),
            ),
            const SizedBox(height: 10),
            TranslatedText(
              'Veuillez confirmer sur votre téléphone pour finaliser le paiement. Ne fermez pas cette page.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: textSecondary),
            ),
          ],
        );
      case _FlexPayState.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppThemeData.success400, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Paiement réussi !'.tr, style: TextStyle(fontSize: 20, fontFamily: AppThemeData.bold, color: textPrimary)),
          ],
        );
      case _FlexPayState.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, color: AppThemeData.danger300, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Paiement échoué'.tr, style: TextStyle(fontSize: 20, fontFamily: AppThemeData.bold, color: textPrimary)),
            const SizedBox(height: 8),
            TranslatedText(
              'Le paiement n\'a pas pu être confirmé. Vous n\'avez pas été débité. Vous pouvez réessayer depuis le récapitulatif de commande.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: BorderSide(color: AppThemeData.primary300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                onPressed: () => Get.back(result: false),
                child: TranslatedText('Retour au récapitulatif'.tr, style: TextStyle(color: AppThemeData.primary300, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      case _FlexPayState.timeout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.access_time, color: AppThemeData.warning300, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Délai dépassé'.tr, style: TextStyle(fontSize: 18, fontFamily: AppThemeData.bold, color: textPrimary)),
            const SizedBox(height: 10),
            TranslatedText(
              'Si le montant a été débité, contactez le support. Sinon, vérifiez à nouveau.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppThemeData.primary300, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                onPressed: _submitting ? null : _checkNow,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : TranslatedText('Vérifier maintenant'.tr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
    }
  }
}
