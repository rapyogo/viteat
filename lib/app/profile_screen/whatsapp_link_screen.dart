import 'package:cloud_functions/cloud_functions.dart';
import 'package:customer/constant/show_toast_dialog.dart';
import 'package:customer/services/whatsapp_link_service.dart';
import 'package:customer/themes/app_them_data.dart';
import 'package:customer/themes/round_button_fill.dart';
import 'package:customer/utils/dark_theme_provider.dart';
import 'package:customer/widget/translated_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class WhatsAppLinkScreen extends StatefulWidget {
  const WhatsAppLinkScreen({super.key});

  @override
  State<WhatsAppLinkScreen> createState() => _WhatsAppLinkScreenState();
}

class _WhatsAppLinkScreenState extends State<WhatsAppLinkScreen> {
  String? _command;
  bool _isLoading = false;

  Future<void> _generateCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final data = await WhatsAppLinkService.createCode();
      if (!mounted) return;
      setState(() => _command = data['whatsappCommand']?.toString());
    } on FirebaseFunctionsException catch (error) {
      ShowToastDialog.showToast(error.message ?? "Unable to create the WhatsApp link code.");
    } catch (_) {
      ShowToastDialog.showToast("Unable to create the WhatsApp link code.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyCommand() async {
    if (_command == null) return;
    await Clipboard.setData(ClipboardData(text: _command!));
    ShowToastDialog.showToast("Code copied. Send it to Viteat on WhatsApp.");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DarkThemeProvider>(context);
    final isDark = theme.getThem();
    final surface = isDark ? AppThemeData.grey900 : AppThemeData.grey50;
    final textColor = isDark ? AppThemeData.grey50 : AppThemeData.grey900;
    final muted = isDark ? AppThemeData.grey400 : AppThemeData.grey500;

    return Scaffold(
      backgroundColor: isDark ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppThemeData.surfaceDark : AppThemeData.surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textColor),
        title: TranslatedText("Link WhatsApp", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 20, color: textColor)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFE7F8EE), borderRadius: BorderRadius.circular(16)),
                child: SvgPicture.asset("assets/icons/ic_whatsapp.svg", width: 30, height: 30),
              ),
              const SizedBox(height: 18),
              TranslatedText("Order and track on WhatsApp", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 24, color: textColor)),
              const SizedBox(height: 8),
              TranslatedText(
                "Securely connect your Viteat account to the WhatsApp number registered on your profile.",
                style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 15, height: 1.45, color: muted),
              ),
              const SizedBox(height: 24),
              _stepsCard(surface, textColor, muted),
              const SizedBox(height: 18),
              if (_command != null) _codeCard(surface, textColor, muted),
              if (_command != null) const SizedBox(height: 18),
              RoundedButtonFill(
                title: _isLoading ? "Please wait" : (_command == null ? "Generate WhatsApp code" : "Generate a new code"),
                color: AppThemeData.primary300,
                textColor: AppThemeData.grey50,
                height: 6,
                onPress: _generateCode,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TranslatedText(
                      "Each code expires after 10 minutes and can only be used from your registered WhatsApp number.",
                      style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 12, height: 1.4, color: muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepsCard(Color surface, Color textColor, Color muted) {
    const steps = [
      "Generate your one-time code below.",
      "Open the Viteat WhatsApp conversation from your registered number.",
      "Send the copied command to confirm the connection.",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslatedText("How it works", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 16, color: textColor)),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (index) => Padding(
                padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppThemeData.primary50, borderRadius: BorderRadius.circular(12)),
                      child: Text("${index + 1}", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 12, color: AppThemeData.primary300)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: TranslatedText(steps[index], style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 14, height: 1.35, color: muted))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _codeCard(Color surface, Color textColor, Color muted) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(border: Border.all(color: AppThemeData.primary200), color: surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslatedText("Your WhatsApp command", style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 14, color: textColor)),
          const SizedBox(height: 8),
          SelectableText(_command!, style: TextStyle(fontFamily: AppThemeData.bold, fontSize: 20, letterSpacing: 1.2, color: AppThemeData.primary300)),
          const SizedBox(height: 4),
          TranslatedText("Copy this command and send it to Viteat on WhatsApp.", style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 12, color: muted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _copyCommand,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: TranslatedText("Copy command"),
            style: OutlinedButton.styleFrom(foregroundColor: AppThemeData.primary300, side: BorderSide(color: AppThemeData.primary300)),
          ),
        ],
      ),
    );
  }
}
