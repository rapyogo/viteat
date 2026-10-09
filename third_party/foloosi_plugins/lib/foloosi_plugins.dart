
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class FoloosiPlugins {
  static const MethodChannel _channel = MethodChannel('foloosi_plugins');

  static init(String initData) {
    _channel.invokeMethod('init', <String, dynamic>{"public_key": initData});
  }

  static Future<dynamic> makePayment(String orderData) async {
    dynamic version = await _channel.invokeMethod(
        'makePayment', <String, dynamic>{"order_data": orderData});
    return json.decode(version);
  }

  static Future<dynamic> makePaymentWithReferenceToken(
      String referenceToken) async {
    dynamic version = await _channel.invokeMethod(
        'makePaymentWithReferenceToken',
        <String, dynamic>{"reference_token": referenceToken});
    return json.decode(version);
  }

  static setLogVisible(bool debug) {
    _channel.invokeMethod('setLogVisible', <String, dynamic>{"visible": debug});
  }
}
