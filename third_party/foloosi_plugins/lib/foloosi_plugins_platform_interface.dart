import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'foloosi_plugins_method_channel.dart';

abstract class FoloosiPluginsPlatform extends PlatformInterface {
  /// Constructs a FoloosiPluginsPlatform.
  FoloosiPluginsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FoloosiPluginsPlatform _instance = MethodChannelFoloosiPlugins();

  /// The default instance of [FoloosiPluginsPlatform] to use.
  ///
  /// Defaults to [MethodChannelFoloosiPlugins].
  static FoloosiPluginsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FoloosiPluginsPlatform] when
  /// they register themselves.
  static set instance(FoloosiPluginsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
