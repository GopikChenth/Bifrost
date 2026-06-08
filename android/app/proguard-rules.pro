# Keep Flutter and plugin entry points available after R8 optimization,
# but exclude Play Store dynamic features/deferred components so R8 can strip play-core.
-keep class !io.flutter.embedding.android.FlutterPlayStoreSplitApplication, !io.flutter.embedding.engine.deferredcomponents.**, io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native method owners stable for JNI lookups.
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class com.arcadelabs.bifrost.LocalJvmBridge { *; }

# Keep Google API models used by Drive sync serialization.
-keep class com.google.api.services.drive.** { *; }
-keep class com.google.api.client.** { *; }

# Keep archive/runtime extraction dependency metadata.
-keep class org.tukaani.xz.** { *; }

# Flutter references Play Store deferred-component classes even when the app
# does not use deferred components.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
