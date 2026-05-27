package com.arcadelabs.bifrost

import android.os.Build
import java.io.File
import java.io.IOException

data class BundledRuntime(
    val javaMajor: Int,
    val assetPath: String,
    val installName: String,
    val libDirectory: String,
    val jliRelativePath: String,
    val jvmRelativePath: String,
    val moduleOrClasspathMarker: String,
) {
    fun installHome(runtimeRoot: File): File = File(runtimeRoot, "java/$installName")

    fun architectureArchiveName(): String {
        return when (Build.SUPPORTED_ABIS.firstOrNull().orEmpty()) {
            "arm64-v8a" -> "bin-arm64.tar.xz"
            "armeabi-v7a" -> "bin-arm.tar.xz"
            "x86_64" -> "bin-x86_64.tar.xz"
            "x86" -> "bin-x86.tar.xz"
            else -> throw IOException("Unsupported Android ABI for bundled Java runtime.")
        }
    }
}

object BundledRuntimeCatalog {
    private val runtimes = listOf(
        BundledRuntime(
            javaMajor = 8,
            assetPath = "app_runtime/java/jre8",
            installName = "jre8",
            libDirectory = "lib/aarch64",
            jliRelativePath = "lib/aarch64/jli/libjli.so",
            jvmRelativePath = "lib/aarch64/server/libjvm.so",
            moduleOrClasspathMarker = "lib/rt.jar",
        ),
        BundledRuntime(
            javaMajor = 17,
            assetPath = "app_runtime/java/jre17",
            installName = "jre17",
            libDirectory = "lib",
            jliRelativePath = "lib/libjli.so",
            jvmRelativePath = "lib/server/libjvm.so",
            moduleOrClasspathMarker = "lib/modules",
        ),
        BundledRuntime(
            javaMajor = 21,
            assetPath = "app_runtime/java/jre21",
            installName = "jre21",
            libDirectory = "lib",
            jliRelativePath = "lib/libjli.so",
            jvmRelativePath = "lib/server/libjvm.so",
            moduleOrClasspathMarker = "lib/modules",
        ),
        BundledRuntime(
            javaMajor = 25,
            assetPath = "app_runtime/java/jre25",
            installName = "jre25",
            libDirectory = "lib",
            jliRelativePath = "lib/libjli.so",
            jvmRelativePath = "lib/server/libjvm.so",
            moduleOrClasspathMarker = "lib/modules",
        ),
    )

    fun byJavaMajor(javaMajor: Int): BundledRuntime {
        return runtimes.firstOrNull { it.javaMajor == javaMajor }
            ?: throw IOException("Java $javaMajor runtime is not bundled.")
    }

    fun chooseForMinecraftVersion(version: String): BundledRuntime {
        val parts = Regex("\\d+")
            .findAll(version)
            .mapNotNull { it.value.toIntOrNull() }
            .filter { it > 0 }
            .toList()
        val featureVersion = when {
            parts.isEmpty() -> 21
            parts.first() == 1 && parts.size > 1 -> parts[1]
            else -> parts.first()
        }
        return byJavaMajor(javaMajorForMinecraftFeature(featureVersion))
    }

    fun javaMajorForMinecraftFeature(featureVersion: Int): Int {
        return when {
            featureVersion >= 26 -> 25
            featureVersion >= 20 -> 21
            featureVersion >= 18 -> 17
            else -> 8
        }
    }
}
