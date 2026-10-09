#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint foloosi_plugins.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'foloosi_plugins'
  s.version          = '1.1.0'
  s.summary          = 'A Flutter plugin for making payments via Foloosi Payment Gateway. Fully supports Android and iOS.'
  s.description      = <<-DESC
A Flutter plugin for making payments via Foloosi Payment Gateway. Fully supports Android and iOS.
                       DESC
  s.homepage         = 'http://www.foloosi.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Foloosi' => 'apps@foloosi.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'Foloosi-iOS-SDK','~> 1.5.1'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'foloosi_plugins_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
