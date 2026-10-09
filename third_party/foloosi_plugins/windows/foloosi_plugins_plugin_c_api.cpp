#include "include/foloosi_plugins/foloosi_plugins_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "foloosi_plugins_plugin.h"

void FoloosiPluginsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  foloosi_plugins::FoloosiPluginsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
