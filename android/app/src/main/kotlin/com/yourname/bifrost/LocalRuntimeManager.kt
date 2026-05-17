package com.yourname.bifrost

import android.app.ActivityManager
import android.content.Context
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
    private val tag = "bifrost-local-runtime"
    @Volatile
    private var activeRuntimeMajor = 21
    @Volatile
    private var launchThread: Thread? = null
    @Volatile
    private var activeServerPath: String? = null
    @Volatile
    private var lastExitCode: Int? = null
    @Volatile
    private var stopRequested = false
    @Volatile
    private var runtimeInitialized = false
    private val serverState = AtomicReference("idle")
    private val lastMessage = AtomicReference<String?>(null)

    private val runtimeHome: File
        get() = BundledRuntimeCatalog.byJavaMajor(activeRuntimeMajor).installHome(runtimeRoot)

    fun getRuntimeStatus(): Map<String, Any> {
        val runtime = BundledRuntimeCatalog.byJavaMajor(activeRuntimeMajor)
        val runtimeLibDir = resolveRuntimeLibDir(runtimeHome)
        return mapOf(
            "runtimeRoot" to runtimeRoot.absolutePath,
            "runtimeHome" to runtimeHome.absolutePath,
            "runtimeMajor" to activeRuntimeMajor,
            "runtimeHomeExists" to runtimeHome.exists(),
            "releaseExists" to File(runtimeHome, "release").exists(),
            "libDir" to runtimeLibDir.absolutePath,
            "libDirExists" to runtimeLibDir.exists(),
            "libjliExists" to File(runtimeHome, runtime.jliRelativePath).exists(),
            "libjvmExists" to File(runtimeHome, runtime.jvmRelativePath).exists(),
            "modulesExists" to File(runtimeHome, runtime.moduleOrClasspathMarker).exists(),
        )
    }

    @Throws(IOException::class)
    @Synchronized
    fun prepareBundledRuntimeHome(runtimeMajor: Int = activeRuntimeMajor) {
        val runtime = BundledRuntimeCatalog.byJavaMajor(runtimeMajor)
        if (activeRuntimeMajor != runtime.javaMajor) {
            activeRuntimeMajor = runtime.javaMajor
            runtimeInitialized = false
        }
        val selectedRuntimeHome = runtime.installHome(runtimeRoot)
        val selectedRuntimeMarkerFile = File(selectedRuntimeHome, "runtime.version")
        val selectedRuntimeVersion = readRuntimeAssetVersion(runtime)

        if (!runtimeRoot.exists() && !runtimeRoot.mkdirs()) {
            throw IOException("Unable to create runtime root at ${runtimeRoot.absolutePath}")
        }
        cleanupLegacyRuntimeHomes()

        val requiredFiles = listOf(
            runtime.moduleOrClasspathMarker,
            runtime.jliRelativePath,
            runtime.jvmRelativePath,
        )

        val markerMatches =
            selectedRuntimeMarkerFile.exists() &&
                selectedRuntimeMarkerFile.readText().trim() == selectedRuntimeVersion
        if (markerMatches && requiredFiles.all { File(selectedRuntimeHome, it).exists() }) {
            return
        }

        runtimeInitialized = false
        if (selectedRuntimeHome.exists() && !selectedRuntimeHome.deleteRecursively()) {
            throw IOException("Unable to replace runtime home at ${selectedRuntimeHome.absolutePath}")
        }

        selectedRuntimeHome.mkdirs()
        context.assets.open("${runtime.assetPath}/universal.tar.xz").use { input ->
            TarXzExtractor.extract(input, selectedRuntimeHome)
        }
        context.assets.open("${runtime.assetPath}/${runtime.architectureArchiveName()}").use { input ->
            TarXzExtractor.extract(input, selectedRuntimeHome)
        }
        if (runtime.javaMajor == 8) {
            unpackPack200Files(selectedRuntimeHome)
        }
        validateRuntimeInstall(runtime, selectedRuntimeHome)
        selectedRuntimeMarkerFile.writeText("$selectedRuntimeVersion\n")
    }

    fun runJavaVersion(workingDirectory: String?, runtimeMajor: Int = activeRuntimeMajor): Int {
        prepareBundledRuntimeHome(runtimeMajor)
        val launchDirectory =
            workingDirectory?.takeIf { it.isNotBlank() } ?: runtimeHome.absolutePath
        prepareEnvironment(workingDirectory)
        return LocalJvmBridge.launchJVM(
            arrayOf(
                "java",
                "-Djava.home=${runtimeHome.absolutePath}",
                "-Duser.home=${runtimeHome.absolutePath}",
                "-Djava.io.tmpdir=${context.cacheDir.absolutePath}",
                "-Duser.dir=$launchDirectory",
                "-Duser.language=${System.getProperty("user.language") ?: "en"}",
                "-Djava.awt.headless=true",
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
        runtimeMajor: Int = 21,
    ): Map<String, Any?> {
        val existingThread = launchThread
        if (existingThread != null && existingThread.isAlive) {
            throw IllegalStateException(
                "A server is already ${serverState.get()} for $activeServerPath.",
            )
        }

        activeServerPath = serverPath
        lastExitCode = null
        stopRequested = false
        serverState.set("starting")
        lastMessage.set("Preparing the local runtime.")

        val thread = Thread {
            try {
                prepareBundledRuntimeHome(runtimeMajor)
                prepareEnvironment(serverPath)

                serverState.set("starting")
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
                        "-Djava.awt.headless=true",
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
                if (stopRequested) {
                    serverState.set("stopped")
                    lastMessage.set("Server stopped.")
                } else {
                    serverState.set(if (exitCode == 0) "stopped" else "error")
                    lastMessage.set("Server exited with code $exitCode.")
                }
            } catch (error: Throwable) {
                if (stopRequested) {
                    serverState.set("stopped")
                    lastMessage.set("Server stopped.")
                } else {
                    serverState.set("error")
                    lastMessage.set(error.localizedMessage ?: "Local server launch failed.")
                }
            } finally {
                launchThread = null
            }
        }
        thread.name = "bifrost-local-server"
        launchThread = thread
        thread.start()

        return getServerStatus()
    }

    @Synchronized
    fun stopServer(): Map<String, Any?> {
        val thread = launchThread
        if (thread == null || !thread.isAlive) {
            serverState.set("stopped")
            lastMessage.set("No active server process is running.")
            return getServerStatus()
        }

        stopRequested = true
        serverState.set("stopping")
        lastMessage.set("Sending graceful stop command to the local server.")

        val stopResult = LocalJvmBridge.stopJVM()
        if (stopResult < 0) {
            serverState.set("error")
            lastMessage.set("Unable to send graceful stop command to the local server.")
            return getServerStatus()
        }

        Thread {
            try {
                Thread.sleep(15000)
                val activeThread = launchThread
                if (stopRequested && activeThread != null && activeThread.isAlive) {
                    LocalJvmBridge.terminateJVM()
                    lastMessage.set("Server did not stop gracefully, sending SIGTERM.")
                }

                Thread.sleep(4000)
                val stillActiveThread = launchThread
                if (stopRequested && stillActiveThread != null && stillActiveThread.isAlive) {
                    LocalJvmBridge.forceStopJVM()
                    lastMessage.set("Server did not stop after SIGTERM, forcing shutdown.")
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }.apply {
            name = "bifrost-local-server-force-stop"
            start()
        }

        return getServerStatus()
    }

    fun sendServerCommand(command: String): Map<String, Any?> {
        val trimmedCommand = command.trim()
        if (trimmedCommand.isEmpty()) {
            throw IllegalArgumentException("Command cannot be empty.")
        }

        val thread = launchThread
        if (thread == null || !thread.isAlive || serverState.get() != "running") {
            throw IllegalStateException("No online Minecraft server is ready for commands.")
        }

        val result = LocalJvmBridge.sendJVMCommand(trimmedCommand)
        if (result < 0) {
            throw IOException("Unable to send command to the Minecraft server.")
        }
        if (result == 0) {
            throw IllegalStateException("Minecraft server input is not connected.")
        }

        lastMessage.set("Command sent: $trimmedCommand")
        return getServerStatus()
    }

    fun getServerStatus(): Map<String, Any?> {
        if (serverState.get() == "starting" && LocalJvmBridge.isJVMReady()) {
            serverState.set("running")
            lastMessage.set("Minecraft server is online.")
        }

        return mapOf(
            "state" to serverState.get(),
            "activeServerPath" to activeServerPath,
            "lastExitCode" to lastExitCode,
            "lastMessage" to lastMessage.get(),
            "consoleOutput" to LocalJvmBridge.getJVMOutput(),
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

    private fun readRuntimeAssetVersion(runtime: BundledRuntime): String {
        return context.assets.open("${runtime.assetPath}/version").use { input ->
            input.bufferedReader().readText().trim()
        }
    }

    private fun unpackPack200Files(runtimeHome: File) {
        val unpacker = File(context.applicationInfo.nativeLibraryDir, "libunpack200.so")
        if (!unpacker.exists()) {
            throw IOException("Java 8 pack200 unpacker is missing at ${unpacker.absolutePath}")
        }

        val packedFiles = runtimeHome.walkTopDown()
            .filter { it.isFile && it.name.endsWith(".pack") }
            .toList()

        for (packFile in packedFiles) {
            val outputFile = File(packFile.parentFile, packFile.name.removeSuffix(".pack"))
            try {
                val process = ProcessBuilder(
                    "./${unpacker.name}",
                    "-r",
                    packFile.absolutePath,
                    outputFile.absolutePath,
                )
                    .directory(File(context.applicationInfo.nativeLibraryDir))
                    .redirectErrorStream(true)
                    .start()
                val output = process.inputStream.bufferedReader().readText().trim()
                val exitCode = process.waitFor()
                if (exitCode != 0) {
                    throw IOException(
                        "unpack200 failed for ${packFile.absolutePath} with exit=$exitCode $output",
                    )
                }
            } catch (error: Throwable) {
                if (error is InterruptedException) {
                    Thread.currentThread().interrupt()
                }
                throw IOException("Unable to unpack ${packFile.absolutePath}", error)
            }
        }
    }

    private fun validateRuntimeInstall(runtime: BundledRuntime, runtimeHome: File) {
        val missingFiles = listOf(
            runtime.moduleOrClasspathMarker,
            runtime.jliRelativePath,
            runtime.jvmRelativePath,
        ).filterNot { File(runtimeHome, it).exists() }

        if (missingFiles.isNotEmpty()) {
            throw IOException(
                "Java ${runtime.javaMajor} runtime install is incomplete. Missing: ${missingFiles.joinToString()}",
            )
        }
    }

    private fun cleanupLegacyRuntimeHomes() {
        listOf("Internal-8", "Internal-17", "Internal-21", "Internal-25").forEach { legacyName ->
            val legacyHome = File(runtimeRoot, legacyName)
            if (legacyHome.exists() && !legacyHome.deleteRecursively()) {
                Log.w(tag, "Unable to delete legacy runtime home ${legacyHome.absolutePath}")
            }
        }
    }

    private fun prepareEnvironment(workingDirectory: String?) {
        val libDir = resolveRuntimeLibDir(runtimeHome)
        val serverLibDir = File(libDir, "server")
        val jliLibDir = File(libDir, "jli")
        val ldLibraryPath = buildString {
            append(serverLibDir.absolutePath)
            append(':')
            if (jliLibDir.exists()) {
                append(jliLibDir.absolutePath)
                append(':')
            }
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

    @Synchronized
    private fun initializeJvmRuntime() {
        if (runtimeInitialized) {
            Log.d(tag, "Runtime native libraries already initialized")
            return
        }

        val libDir = resolveRuntimeLibDir(runtimeHome)
        val coreLibsToLoad = listOf(
            File(libDir, "libjli.so").absolutePath,
            File(libDir, "server/libjvm.so").absolutePath,
            File(libDir, "libverify.so").absolutePath,
            File(libDir, "libjava.so").absolutePath,
            File(libDir, "libnet.so").absolutePath,
            File(libDir, "libnio.so").absolutePath,
            File(libDir, "libzip.so").absolutePath,
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

        runtimeInitialized = true
    }

    private fun resolveRuntimeLibDir(home: File): File {
        return File(home, BundledRuntimeCatalog.byJavaMajor(activeRuntimeMajor).libDirectory)
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
                    !isGraphicsRuntimeLibrary(file.name) &&
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
            else -> 100
        }
    }

    private fun isGraphicsRuntimeLibrary(fileName: String): Boolean {
        return fileName in setOf(
            "libawt.so",
            "libawt_headless.so",
            "libfontmanager.so",
            "libfreetype.so",
            "libjawt.so",
            "libjavajpeg.so",
            "liblcms.so",
            "libmlib_image.so",
        )
    }

}
