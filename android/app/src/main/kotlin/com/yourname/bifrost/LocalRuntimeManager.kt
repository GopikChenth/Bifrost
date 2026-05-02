package com.yourname.bifrost

import android.app.ActivityManager
import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import android.system.Os
import android.util.Log
import java.io.File
import java.io.IOException
import java.util.concurrent.atomic.AtomicReference

class LocalRuntimeManager(
    private val context: Context,
) {
    private val runtimeRoot: File = File(context.filesDir, "runtimes")
    private val runtimeHome: File = File(runtimeRoot, "Internal-21")
    private val tag = "bifrost-local-runtime"
    @Volatile
    private var launchThread: Thread? = null
    @Volatile
    private var activeServerPath: String? = null
    @Volatile
    private var lastExitCode: Int? = null
    private val serverState = AtomicReference("idle")
    private val lastMessage = AtomicReference<String?>(null)

    fun getRuntimeStatus(): Map<String, Any> {
        val runtimeLibDir = resolveRuntimeLibDir(runtimeHome)
        return mapOf(
            "runtimeRoot" to runtimeRoot.absolutePath,
            "runtimeHome" to runtimeHome.absolutePath,
            "runtimeHomeExists" to runtimeHome.exists(),
            "releaseExists" to File(runtimeHome, "release").exists(),
            "libDir" to runtimeLibDir.absolutePath,
            "libDirExists" to runtimeLibDir.exists(),
            "libjliExists" to File(runtimeLibDir, "libjli.so").exists(),
            "libjvmExists" to File(runtimeLibDir, "server/libjvm.so").exists(),
            "modulesExists" to File(runtimeLibDir, "modules").exists(),
        )
    }

    @Throws(IOException::class)
    fun prepareBundledRuntimeHome() {
        if (!runtimeRoot.exists() && !runtimeRoot.mkdirs()) {
            throw IOException("Unable to create runtime root at ${runtimeRoot.absolutePath}")
        }

        val requiredFiles = listOf(
            "lib/modules",
            "lib/libjli.so",
            "lib/server/libjvm.so",
        )

        if (requiredFiles.all { File(runtimeHome, it).exists() }) {
            return
        }

        copyAssetDirectory(context.assets, "jre-home", runtimeHome)
    }

    fun runJavaVersion(workingDirectory: String?): Int {
        val launchDirectory =
            workingDirectory?.takeIf { it.isNotBlank() } ?: runtimeHome.absolutePath
        prepareEnvironment(workingDirectory)
        initializeJvmRuntime()
        return LocalJvmBridge.launchJVM(
            arrayOf(
                "java",
                "-Djava.home=${runtimeHome.absolutePath}",
                "-Duser.home=${runtimeHome.absolutePath}",
                "-Djava.io.tmpdir=${context.cacheDir.absolutePath}",
                "-Duser.dir=$launchDirectory",
                "-Duser.language=${System.getProperty("user.language") ?: "en"}",
                "-Dos.name=Linux",
                "-Dos.version=Android-${Build.VERSION.RELEASE}",
                "-Djdk.lang.Process.launchMechanism=FORK",
                "-version",
            ),
        )
    }

    @Synchronized
    fun startServer(
        serverPath: String,
        jarPath: String,
        maxRamMb: Int,
    ): Map<String, Any?> {
        val existingThread = launchThread
        if (existingThread != null && existingThread.isAlive) {
            throw IllegalStateException(
                "A server is already ${serverState.get()} for $activeServerPath.",
            )
        }

        activeServerPath = serverPath
        lastExitCode = null
        serverState.set("starting")
        lastMessage.set("Preparing the local runtime.")

        val thread = Thread {
            try {
                prepareBundledRuntimeHome()
                prepareEnvironment(serverPath)
                initializeJvmRuntime()

                serverState.set("running")
                lastMessage.set("Launching $jarPath")

                val safeMaxRam = computeSafeMaxRam(maxRamMb)
                val safeMinRam = minOf(512, safeMaxRam)
                Log.d(tag, "RAM: requested=${maxRamMb}M, safeMax=${safeMaxRam}M, safeMin=${safeMinRam}M")
                val exitCode = LocalJvmBridge.launchJVM(
                    arrayOf(
                        "java",
                        "-Djava.home=${runtimeHome.absolutePath}",
                        "-Duser.home=$serverPath",
                        "-Djava.io.tmpdir=${context.cacheDir.absolutePath}",
                        "-Duser.dir=$serverPath",
                        "-Duser.language=${System.getProperty("user.language") ?: "en"}",
                        "-Dos.name=Linux",
                        "-Dos.version=Android-${Build.VERSION.RELEASE}",
                        "-Djdk.lang.Process.launchMechanism=FORK",
                        "-Xms${safeMinRam}M",
                        "-Xmx${safeMaxRam}M",
                        "-jar",
                        jarPath,
                        "nogui",
                    ),
                )

                lastExitCode = exitCode
                serverState.set(if (exitCode == 0) "stopped" else "error")
                lastMessage.set("Server exited with code $exitCode.")
            } catch (error: Throwable) {
                serverState.set("error")
                lastMessage.set(error.localizedMessage ?: "Local server launch failed.")
            } finally {
                launchThread = null
            }
        }
        thread.name = "bifrost-local-server"
        launchThread = thread
        thread.start()

        return getServerStatus()
    }

    fun getServerStatus(): Map<String, Any?> {
        return mapOf(
            "state" to serverState.get(),
            "activeServerPath" to activeServerPath,
            "lastExitCode" to lastExitCode,
            "lastMessage" to lastMessage.get(),
        )
    }

    private fun computeSafeMaxRam(requestedMb: Int): Int {
        return try {
            val memInfo = ActivityManager.MemoryInfo()
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.getMemoryInfo(memInfo)
            val availableMb = (memInfo.availMem / (1024L * 1024L)).toInt()
            val safeCap = (availableMb * 0.6).toInt()
            val result = minOf(requestedMb, safeCap, 3072).coerceAtLeast(512)
            Log.d(tag, "Device available RAM: ${availableMb}M, safe cap: ${safeCap}M, final: ${result}M")
            result
        } catch (error: Throwable) {
            Log.w(tag, "Unable to query device memory, falling back to 2048M", error)
            minOf(requestedMb, 2048)
        }
    }

    private fun prepareEnvironment(workingDirectory: String?) {
        val libDir = resolveRuntimeLibDir(runtimeHome)
        val serverLibDir = File(libDir, "server")
        val ldLibraryPath = buildString {
            append(serverLibDir.absolutePath)
            append(':')
            append(libDir.absolutePath)
            append(':')
            append(context.applicationInfo.nativeLibraryDir)
            append(":/system/lib64:/vendor/lib64:/vendor/lib64/hw")
        }

        Os.setenv("JAVA_HOME", runtimeHome.absolutePath, true)
        Os.setenv("HOME", runtimeHome.absolutePath, true)
        Os.setenv("TMPDIR", context.cacheDir.absolutePath, true)
        Os.setenv("LD_LIBRARY_PATH", ldLibraryPath, true)
        Os.setenv("PATH", "${runtimeHome.absolutePath}/bin:${Os.getenv("PATH") ?: ""}", true)
        Log.d(tag, "JAVA_HOME=${runtimeHome.absolutePath}")
        Log.d(tag, "LD_LIBRARY_PATH=$ldLibraryPath")
        LocalJvmBridge.setLdLibraryPath(ldLibraryPath)

        val directory = workingDirectory?.takeIf { it.isNotBlank() } ?: runtimeHome.absolutePath
        LocalJvmBridge.chdir(directory)
    }

    private fun initializeJvmRuntime() {
        val libDir = resolveRuntimeLibDir(runtimeHome)
        val coreLibsToLoad = listOf(
            File(libDir, "libjli.so").absolutePath,
            File(libDir, "server/libjvm.so").absolutePath,
            File(libDir, "libverify.so").absolutePath,
            File(libDir, "libjava.so").absolutePath,
            File(libDir, "libnet.so").absolutePath,
            File(libDir, "libnio.so").absolutePath,
            File(libDir, "libzip.so").absolutePath,
            File(libDir, "libfreetype.so").absolutePath,
            File(libDir, "libawt.so").absolutePath,
            File(libDir, "libawt_headless.so").absolutePath,
            File(libDir, "libfontmanager.so").absolutePath,
        )

        for (libPath in coreLibsToLoad) {
            val file = File(libPath)
            if (!file.exists()) {
                Log.w(tag, "Skipping missing core runtime library $libPath")
                continue
            }
            LocalJvmBridge.dlopen(libPath)
        }

        val loadedCoreSet = coreLibsToLoad.toSet()
        val remainingLibs = collectRuntimeLibraries(libDir)
            .filterNot { it in loadedCoreSet }
            .toMutableList()

        var madeProgress: Boolean
        do {
            madeProgress = false
            val iterator = remainingLibs.iterator()
            while (iterator.hasNext()) {
                val libPath = iterator.next()
                val loaded = LocalJvmBridge.dlopen(libPath)
                if (loaded) {
                    iterator.remove()
                    madeProgress = true
                }
            }
        } while (remainingLibs.isNotEmpty() && madeProgress)

        for (libPath in remainingLibs) {
            Log.w(tag, "Leaving runtime library unloaded: $libPath")
        }
    }

    private fun resolveRuntimeLibDir(home: File): File {
        val aarch64Dir = File(home, "lib/aarch64")
        return if (aarch64Dir.exists()) aarch64Dir else File(home, "lib")
    }

    private fun collectRuntimeLibraries(libDir: File): List<String> {
        if (!libDir.exists()) {
            return emptyList()
        }

        return libDir
            .walkTopDown()
            .filter { file ->
                file.isFile &&
                    file.extension == "so" &&
                    !file.name.startsWith("libjsig")
            }
            .map { it.absolutePath }
            .sortedWith(compareBy(::runtimeLibraryPriority, { it }))
            .toList()
    }

    private fun runtimeLibraryPriority(libPath: String): Int {
        val fileName = File(libPath).name
        return when (fileName) {
            "libjli.so" -> 0
            "libjvm.so" -> 1
            "libverify.so" -> 2
            "libjava.so" -> 3
            "libnet.so" -> 4
            "libnio.so" -> 5
            "libzip.so" -> 6
            "libfreetype.so" -> 7
            "libawt.so" -> 8
            "libawt_headless.so" -> 9
            "libfontmanager.so" -> 10
            else -> 100
        }
    }

    @Throws(IOException::class)
    private fun copyAssetDirectory(
        assetManager: AssetManager,
        assetPath: String,
        destination: File,
    ) {
        val children = assetManager.list(assetPath).orEmpty()
        if (children.isEmpty()) {
            destination.parentFile?.mkdirs()
            assetManager.open(assetPath).use { input ->
                destination.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            return
        }

        if (!destination.exists() && !destination.mkdirs()) {
            throw IOException("Unable to create ${destination.absolutePath}")
        }

        for (child in children) {
            val childAssetPath = if (assetPath.isEmpty()) child else "$assetPath/$child"
            copyAssetDirectory(assetManager, childAssetPath, File(destination, child))
        }
    }
}
