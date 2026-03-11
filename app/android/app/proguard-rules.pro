# Project-specific ProGuard/R8 rules.
# Keep this file minimal unless you add libraries that require custom keep rules.

# ---- OneSignal / OpenTelemetry ----
# OneSignal SDK pulls in OpenTelemetry which references Jackson and AutoValue
# classes that are not present at runtime. Tell R8 to ignore them.
-dontwarn com.fasterxml.jackson.**
-dontwarn io.opentelemetry.**
-dontwarn com.google.auto.value.**

# Keep OneSignal classes
-keep class com.onesignal.** { *; }
