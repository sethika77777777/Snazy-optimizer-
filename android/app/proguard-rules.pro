# Snazy Optimizer — R8/ProGuard rules for the release build.
#
# NOTE: android/app/build.gradle has referenced this exact file since the
# project's first commit (`proguardFiles ..., 'proguard-rules.pro'`), but
# the file itself was never added. minifyEnabled true + a missing proguard
# file is a hard Gradle error, so every `flutter build apk --release` —
# including the project's own CI workflow — was failing before this file
# existed. This isn't a stylistic addition, it's a required fix.

# Flutter's own embedding.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Shizuku API — reflection-instantiates our UserService and talks to it
# entirely through the AIDL-generated Stub/Proxy, so none of these classes
# can be renamed or stripped.
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
-keep interface rikka.shizuku.** { *; }
-keep class com.sethikadv.snazy.IUserService { *; }
-keep class com.sethikadv.snazy.IUserService$* { *; }
-keep class com.sethikadv.snazy.UserService { *; }
-dontwarn rikka.shizuku.**

# Keep our own native-bridge entry points stable — MainActivity is invoked
# by name from the Flutter engine / AndroidManifest, and UserService is
# invoked by name (reflection) from the Shizuku server process.
-keep class com.sethikadv.snazy.MainActivity { *; }
-keep class com.sethikadv.snazy.** { *; }
