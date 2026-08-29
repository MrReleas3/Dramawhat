# ─── Suppress warnings from JS engine libraries ───────────────────────────────
-dontwarn org.mozilla.javascript.**
-dontwarn javax.swing.**

# ─── Flutter / Dart ───────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ─── GetX dependency injection ────────────────────────────────────────────────
# GetX uses class names via reflection to register / find controllers.
# Without these rules R8 obfuscates the names and Get.find<T>() fails,
# producing the "improper use of GetX" error and a black screen on release.
-keep class com.example.** { *; }
-keep class * extends com.google.** { *; }

# Keep ALL classes that extend GetxController, SimpleGetxController, GetxService, etc.
-keep class * extends get.GetxController { *; }
-keep class * extends get.rx_flutter.GetxController { *; }
-keep class * extends getx.** { *; }

# Keep all GetX internals
-keep class get.** { *; }
-keep class getx.** { *; }
-keepnames class get.** { *; }
-keepnames class getx.** { *; }
-dontwarn get.**
-dontwarn getx.**

# Keep all app controllers & services by package
-keep class com.example.vad_app.** { *; }

# ─── Keep all Dart-generated class names (needed by GetX & json_serializable) ─
-keepnames class * { *; }
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# ─── Kotlin reflection ────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# ─── OkHttp / Retrofit / Dio (used for Anify/Kitsu fetch) ────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ─── Suppress common harmless warnings ───────────────────────────────────────
-dontwarn sun.misc.**
-dontwarn java.lang.instrument.**
