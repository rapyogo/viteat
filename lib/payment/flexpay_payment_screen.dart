import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:customer/app/terms_and_condition/terms_and_condition_screen.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/models/payment_model/flexpay_model.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/utils/preferences.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

enum _FlexPayState { form, waiting, success, failed, timeout }

class FlexPayPaymentScreen extends StatefulWidget {
  final FlexPay flexPaySettings;
  final double amount;
  final String currency;
  // Le rechargement du portefeuille peut prendre jusqu'à une minute à se
  // refléter (écriture asynchrone après le retour de cet écran) — on laisse
  // plus de temps de lecture et on prévient l'utilisateur uniquement dans ce
  // cas. En checkout (valeur par défaut), la commande n'est passée qu'au
  // retour de cet écran : on ne retarde pas la redirection automatique.
  final bool isWalletTopUp;

  const FlexPayPaymentScreen({super.key, required this.flexPaySettings, required this.amount, required this.currency, this.isWalletTopUp = false});

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
  Timer? _successRedirectTimer;

  List<String> _recentNumbers = [];

  static const List<String> _waitingTips = [
    "Please confirm on your phone to complete the payment. Don't close this page.",
    'Check your phone for a Mobile Money notification or USSD prompt.',
    'Enter your Mobile Money PIN when prompted to confirm the transaction.',
    'This usually takes less than a minute, but can take up to two.',
    'We are checking your payment status automatically — no need to refresh.',
  ];
  int _waitingTipIndex = 0;
  Timer? _waitingTipTimer;

  @override
  void initState() {
    super.initState();
    _loadRecentNumbers();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timeoutTimer?.cancel();
    _successRedirectTimer?.cancel();
    _waitingTipTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  void _loadRecentNumbers() {
    final String raw = Preferences.getString(Preferences.recentMobileMoneyNumbers, defaultValue: '[]');
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      setState(() => _recentNumbers = decoded.map((e) => e.toString()).toList());
    } catch (_) {
      // Valeur corrompue/legacy — on ignore plutôt que de faire planter l'écran.
    }
  }

  Future<void> _rememberNumber(String number) async {
    final List<String> updated = [number, ..._recentNumbers.where((n) => n != number)].take(3).toList();
    setState(() => _recentNumbers = updated);
    await Preferences.setString(Preferences.recentMobileMoneyNumbers, jsonEncode(updated));
  }

  void _startWaitingTips() {
    _waitingTipIndex = 0;
    _waitingTipTimer?.cancel();
    _waitingTipTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _state != _FlexPayState.waiting) {
        timer.cancel();
        return;
      }
      setState(() => _waitingTipIndex = (_waitingTipIndex + 1) % _waitingTips.length);
    });
  }

  void _onSuccess() {
    _timeoutTimer?.cancel();
    setState(() => _state = _FlexPayState.success);
    _successRedirectTimer?.cancel();
    _successRedirectTimer = Timer(Duration(seconds: widget.isWalletTopUp ? 30 : 2), () {
      if (mounted) Get.back(result: true);
    });
  }

  void _confirmNow() {
    _successRedirectTimer?.cancel();
    Get.back(result: true);
  }

  /// Traduit une erreur technique en explication comprehensible, plutot
  /// qu'un "message d'erreur" generique qui ne dit rien a l'utilisateur.
  String _friendlyErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Payment service is temporarily unavailable. Please try again shortly.';
        case 'invalid-argument':
          return 'The phone number you entered looks invalid. Please check and try again.';
        case 'failed-precondition':
        case 'unavailable-payment-method':
          return 'Mobile Money isn\'t available right now. Please choose another payment method.';
        default:
          return error.message ?? 'Payment could not be initiated. Please try again.';
      }
    }
    return 'Something went wrong. Check your internet connection and try again.';
  }

  String get _normalizedPhone => _phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final String phone = _normalizedPhone;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('initiateMobileMoneyPayment');
      final result = await callable.call({
        'phone': phone,
        'amount': widget.amount,
        'currency': widget.currency,
      });

      final reference = result.data['reference'] as String;
      _reference = reference;
      _rememberNumber(phone);

      setState(() {
        _state = _FlexPayState.waiting;
        _submitting = false;
      });

      _startWaitingTips();
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
        _onSuccess();
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
        _onSuccess();
      } else if (status == 'failed') {
        _timeoutTimer?.cancel();
        setState(() => _state = _FlexPayState.failed);
      } else {
        setState(() {
          _submitting = false;
          _state = _FlexPayState.waiting;
        });
        _startWaitingTips();
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
            child: TranslatedText('Privacy Policy', style: linkStyle),
          ),
          TranslatedText('•', style: TextStyle(color: textSecondary, fontSize: 12)),
          InkWell(
            onTap: () => Get.to(const TermsAndConditionScreen(type: "termAndCondition")),
            child: TranslatedText('Terms & Conditions', style: linkStyle),
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
                'Enter your Mobile Money number',
                style: TextStyle(color: textPrimary, fontFamily: AppThemeData.medium, fontSize: 18),
              ),
              const SizedBox(height: 5),
              TranslatedText(
                'You will receive a payment notification on your phone.',
                style: TextStyle(color: textSecondary, fontFamily: AppThemeData.regular, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: textPrimary),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  hintText: 'e.g. 0812345678'.tr,
                  hintStyle: TextStyle(color: textSecondary, fontSize: 15),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: AppThemeData.primary300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'This field is required.'.tr;
                  }
                  final String normalized = value.trim().replaceAll(RegExp(r'[\s-]'), '');
                  if (!RegExp(r'^(?:\+?243|0)\d{9}$').hasMatch(normalized)) {
                    return 'Invalid number.'.tr;
                  }
                  return null;
                },
              ),
              if (_recentNumbers.isNotEmpty) ...[
                const SizedBox(height: 14),
                TranslatedText(
                  'Recent numbers',
                  style: TextStyle(color: textSecondary, fontFamily: AppThemeData.medium, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _recentNumbers.map((number) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() {
                        _phoneController.text = number;
                        _phoneController.selection = TextSelection.fromPosition(TextPosition(offset: number.length));
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isDark ? AppThemeData.grey700 : AppThemeData.grey200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded, size: 15, color: textSecondary),
                            const SizedBox(width: 6),
                            Text(number, style: TextStyle(color: textPrimary, fontFamily: AppThemeData.medium, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppThemeData.primary300, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : TranslatedText('Continue', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
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
              'A payment request has been sent to your phone',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontFamily: AppThemeData.semiBold, color: textPrimary),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
              child: TranslatedText(
                _waitingTips[_waitingTipIndex],
                key: ValueKey<int>(_waitingTipIndex),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: textSecondary),
              ),
            ),
          ],
        );
      case _FlexPayState.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppThemeData.success400, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Payment successful!', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontFamily: AppThemeData.bold, color: textPrimary)),
            if (widget.isWalletTopUp) ...[
              const SizedBox(height: 10),
              TranslatedText(
                'It can take up to a minute to appear on your wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: BorderSide(color: AppThemeData.primary300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                onPressed: _confirmNow,
                child: TranslatedText('Back', style: TextStyle(color: AppThemeData.primary300, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      case _FlexPayState.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, color: AppThemeData.danger300, size: 64),
            const SizedBox(height: 16),
            TranslatedText('Payment failed', style: TextStyle(fontSize: 20, fontFamily: AppThemeData.bold, color: textPrimary)),
            const SizedBox(height: 8),
            TranslatedText(
              'Payment could not be confirmed. You have not been charged. You can try again from the order summary.',
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
                child: TranslatedText('Back to summary', style: TextStyle(color: AppThemeData.primary300, fontWeight: FontWeight.w700)),
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
            TranslatedText('Timed out', style: TextStyle(fontSize: 18, fontFamily: AppThemeData.bold, color: textPrimary)),
            const SizedBox(height: 10),
            TranslatedText(
              'If the amount was debited, contact support. Otherwise, check again.',
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
                    : TranslatedText('Check now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
    }
  }
}
