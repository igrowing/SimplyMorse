# ─── SimplyNet ProGuard / R8 rules ───────────────────────────────────────────
#
# Flutter's Gradle plugin auto-generates keep rules for the engine.
# We only need explicit rules for:
#   1. Google Play Core split-install classes — referenced by the Flutter
#      engine's PlayStoreDeferredComponentManager but not present in the
#      dependency graph for apps that don't use deferred components.
#      R8 with AGP 9 treats missing referenced classes as a hard error.
#   2. Plugin classes accessed via reflection.

# ── Google Play Core split-install (deferred components) ─────────────────────
# Flutter's engine references these at the bytecode level even when the app
# doesn't use deferred components. They ship in the Play Core library, which
# is an optional dependency. Tell R8 to ignore missing references rather than
# fail the build.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── Flutter engine + plugin bridge ───────────────────────────────────────────
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# ── network_info_plus ─────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.** { *; }

# ── permission_handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── shared_preferences ───────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── path_provider ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── url_launcher ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── Readable crash stack traces ───────────────────────────────────────────────
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
