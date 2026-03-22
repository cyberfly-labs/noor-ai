# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep native methods
-keepclasseswithmembernames class * { native <methods>; }

# Keep Noor AI native bridge
-keep class com.noor.noor_ai.** { *; }
