# Flutter's default ProGuard/R8 keep rules for release builds.
# See https://flutter.dev/docs/deployment/android#enabling-proguard-and-r8

# Keep Flutter's embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native method symbols
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Dart-related symbols
-keep class * implements dart:ffi.Allocatable { *; }
-keep class * implements dart:ffi.NativeType { *; }
