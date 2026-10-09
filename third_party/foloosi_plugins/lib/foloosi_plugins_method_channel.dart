import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'foloosi_plugins_platform_interface.dart';

/// An implementation of [FoloosiPluginsPlatform] that uses method channels.
class MethodChannelFoloosiPlugins extends FoloosiPluginsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('foloosi_plugins');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
