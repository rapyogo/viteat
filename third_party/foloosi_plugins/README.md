foloosi_plugins
=======

A Flutter plugin for making payments via Foloosi Payment Gateway. Fully supports Android and iOS.

# Installation

[See Foloosi SDK for more info.](https://docs.foloosi.com/mobile-sdk-integrations/flutter)

### Dart Versions

```dart version
environment:
  sdk: ^3.11.3
  flutter: '>=3.3.0'
```

# Android Requirement

### Set up Android build.gradle (android/app/build.gradle)

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
    buildTypes {
        release {
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
            signingConfig signingConfigs.release
        }
    }
}
```

### Proguard Rules (Mandatory for release build)

```proguard
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keepattributes JavascriptInterface
-keepattributes Annotation

-dontwarn com.foloosi.**
-keep class com.foloosi.* {*;}

-optimizations !method/inlining/*
```

### Note

- `4.1.0 or higher` is required for settings build.gradle
- `1.4.30 or higher` is required for kotlin version

# iOS Requirement

iOS Deployment Target 13+ (iPhone, iPad)

### SDK Properties Note

If you are using the Foloosi secret and merchant keys as a string in flutter, remember to escape the
$ dollar signs although it is recommended to load these from your backend