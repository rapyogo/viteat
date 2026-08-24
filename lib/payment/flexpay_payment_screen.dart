import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/models/payment_model/flexpay_model.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    } on FirebaseFunctionsException catch (e) {
      setState(() => _submitting = false);
      ShowToastDialog.showToast(e.message ?? 'Échec du paiement.');
    } catch (e) {
      setState(() => _submitting = false);
      ShowToastDialog.showToast('Échec du paiement. Veuillez réessayer.');
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
      ShowToastDialog.showToast('Impossible de vérifier le statut pour le moment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Get.back(result: false),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Icon(Icons.arrow_back_outlined),
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: Icon(Icons.phone_android_rounded, size: 64, color: const Color(0xff204a6a)),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TranslatedText(
                    'Mobile Money'.tr,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 40),
                _buildBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _FlexPayState.form:
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslatedText(
                'Entrez votre numéro Mobile Money'.tr,
                style: const TextStyle(color: Color(0xff2e2e2e), fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              TranslatedText(
                'Vous recevrez une notification de paiement sur votre téléphone.'.tr,
                style: const TextStyle(color: Color(0xff2e2e2e), fontSize: 14, fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  hintText: 'ex : 0812345678',
                  hintStyle: const TextStyle(color: Color.fromARGB(255, 151, 150, 150), fontSize: 15),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xff204a6a))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xffdcdcdc))),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff204a6a), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
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
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xff204a6a))),
            const SizedBox(height: 24),
            TranslatedText(
              'Une demande de paiement a été envoyée sur votre téléphone'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
            ),
            const SizedBox(height: 10),
            TranslatedText(
              'Veuillez confirmer sur votre téléphone pour finaliser le paiement. Ne fermez pas cette page.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        );
      case _FlexPayState.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Paiement réussi !'.tr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black)),
          ],
        );
      case _FlexPayState.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Paiement échoué'.tr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black)),
            const SizedBox(height: 20),
            TextButton(onPressed: () => Get.back(result: false), child: TranslatedText('Retour'.tr)),
          ],
        );
      case _FlexPayState.timeout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.access_time, color: Colors.orange, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Délai dépassé'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black)),
            const SizedBox(height: 10),
            TranslatedText(
              'Si le montant a été débité, contactez le support. Sinon, vérifiez à nouveau.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff204a6a), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
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
