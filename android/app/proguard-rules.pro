# ─── SimplyMorse ProGuard / R8 rules ───────────────────────────────────────────
#
# Flutter's Gradle plugin auto-generates keep rules for the engine.
# We only need explicit rules for plugin classes accessed via reflection.

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── Flutter engine + plugin bridge ───────────────────────────────────────────
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# ── audioplayers ──────────────────────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }

# ── camera ────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.camera.** { *; }

# ── torch_light ───────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.torchlight.** { *; }
-keep class com.example.torch_light.** { *; }
-dontwarn com.example.torch_light.**

# ── record (audio recording) ──────────────────────────────────────────────────
-keep class com.llfbandit.record.** { *; }

# ── share_plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }

# ── shared_preferences ────────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── path_provider ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── Readable crash stack traces ───────────────────────────────────────────────
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
