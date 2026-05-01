package com.yourname.bifrost

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val runningProcesses =
        ConcurrentHashMap<String, RunningServerProcess>()
    private var processEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Disable MTE/heap tagging at the native level as early as possible,
        // before ART's JIT thread pool is fully active. This prevents both
        // "pointer tag was truncated" SIGABRT in the bundled JRE and
        // "futex requeue failed" crashes in ART's ConditionVariable on
        // MIUI/Android 12 devices.
        MteCompat.disable()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/jre",
        ).setMethodCallHandler(::handleJreMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/foreground_server",
        ).setMethodCallHandler(::handleForegroundMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/file_manager",
        ).setMethodCallHandler(::handleFileManagerMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/android_process",
        ).setMethodCallHandler(::handleProcessMethodCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/android_process/events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    processEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    processEventSink = null
                }
            },
        )
    }

    private fun handleJreMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "isInstalled" -> {
                result.success(resolveBundledJavaBinary().exists() && resolveBundledJavaHome().exists())
            }

            "prepareRuntimeHome" -> {
                try {
                    prepareBundledRuntimeHome()
                    result.success(null)
                } catch (error: IOException) {
                    result.error(
                        "JRE_HOME_PREPARE_FAILED",
                        error.message ?: "Unable to prepare the bundled Android JRE home.",
                        null,
                    )
                }
            }

            "getRuntimeStatus" -> {
                val javaBinary = resolveBundledJavaBinary()
                val javaHome = resolveBundledJavaHome()
                result.success(
                    mapOf(
                        "javaBinaryPath" to javaBinary.absolutePath,
                        "javaBinaryExists" to javaBinary.exists(),
                        "javaHomePath" to javaHome.absolutePath,
                        "javaHomeExists" to javaHome.exists(),
                        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                    ),
                )
            }

            "resolveRuntime" -> {
                val javaBinary = resolveBundledJavaBinary()
                val javaHome = resolveBundledJavaHome()

                if (!javaBinary.exists()) {
                    result.error(
                        "JRE_NOT_INSTALLED",
                        "No bundled Android JRE executable was found at ${javaBinary.absolutePath}.",
                        null,
                    )
                    return
                }

                if (!javaHome.exists()) {
                    result.error(
                        "JRE_HOME_MISSING",
                        "No bundled Android JRE home was found at ${javaHome.absolutePath}.",
                        null,
                    )
                    return
                }

                result.success(
                    mapOf(
                        "javaBinaryPath" to javaBinary.absolutePath,
                        "runtimeRootPath" to javaHome.absolutePath,
                        "versionLabel" to "Bundled Android JRE 21",
                    ),
                )
            }

            "runSmokeTest" -> {
                try {
                    val smokeTestResult = runJavaSmokeTest()
                    result.success(smokeTestResult)
                } catch (error: IOException) {
                    result.error(
                        "JRE_SMOKE_TEST_FAILED",
                        error.message ?: "Unable to run the bundled Android JRE smoke test.",
                        null,
                    )
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun handleForegroundMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "start", "update", "stop" -> {
                // Foreground service wiring will be added next.
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun handleFileManagerMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "openFolder" -> {
                val folderPath = call.argument<String>("folderPath")?.trim().orEmpty()
                if (folderPath.isEmpty()) {
                    result.error(
                        "INVALID_FOLDER_PATH",
                        "folderPath is required.",
                        null,
                    )
                    return
                }

                try {
                    val encodedPath = Uri.encode(getDocumentProviderPath(folderPath))
                    val uri =
                        Uri.parse("content://com.android.externalstorage.documents/document/$encodedPath")
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        setDataAndType(uri, "*/*")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        putExtra("android.provider.extra.INITIAL_URI", uri)
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (error: Exception) {
                    result.error(
                        "OPEN_FOLDER_FAILED",
                        error.localizedMessage ?: "Unable to open the requested folder.",
                        null,
                    )
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun handleProcessMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "startProcess" -> startProcess(call, result)
            "sendCommand" -> sendCommand(call, result)
            "stopProcess" -> stopProcess(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startProcess(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val serverPath = call.argument<String>("serverPath")?.trim().orEmpty()
        val serverName = call.argument<String>("serverName")?.trim().orEmpty()
        val executablePath = call.argument<String>("executablePath")?.trim().orEmpty()
        val workingDirectory = call.argument<String>("workingDirectory")?.trim().orEmpty()
        val rawArguments = call.argument<List<*>>("arguments") ?: emptyList<Any?>()
        val arguments = rawArguments.mapNotNull { it?.toString() }

        if (serverPath.isEmpty() || executablePath.isEmpty() || workingDirectory.isEmpty()) {
            result.error(
                "INVALID_START_REQUEST",
                "serverPath, executablePath, and workingDirectory are required.",
                null,
            )
            return
        }

        if (runningProcesses.containsKey(serverPath)) {
            result.error(
                "PROCESS_ALREADY_RUNNING",
                "A server process is already running for $serverPath.",
                null,
            )
            return
        }

        try {
            val command = mutableListOf(executablePath)
            command.addAll(arguments)

            val processBuilder = ProcessBuilder(command)
            processBuilder.directory(File(workingDirectory))
            configureJavaEnvironment(
                processBuilder = processBuilder,
                executablePath = executablePath,
            )

            val process = processBuilder.start()
            val writer = process.outputStream.bufferedWriter()
            val stdoutThread = startStreamPump(
                serverPath = serverPath,
                type = "stdout",
                inputStream = process.inputStream,
            )
            val stderrThread = startStreamPump(
                serverPath = serverPath,
                type = "stderr",
                inputStream = process.errorStream,
            )

            runningProcesses[serverPath] = RunningServerProcess(
                serverName = serverName,
                process = process,
                writer = writer,
                stdoutThread = stdoutThread,
                stderrThread = stderrThread,
            )

            emitProcessEvent(
                type = "started",
                serverPath = serverPath,
                message = "Process started for ${if (serverName.isEmpty()) serverPath else serverName}",
            )

            Thread {
                val exitCode = process.waitFor()
                cleanupProcess(serverPath)
                emitProcessEvent(
                    type = "exited",
                    serverPath = serverPath,
                    exitCode = exitCode,
                )
            }.start()

            result.success(null)
        } catch (error: IOException) {
            result.error(
                "PROCESS_START_FAILED",
                error.message ?: "Unable to start the Android server process.",
                null,
            )
        }
    }

    private fun sendCommand(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val serverPath = call.argument<String>("serverPath")?.trim().orEmpty()
        val command = call.argument<String>("command") ?: ""
        val runningProcess = runningProcesses[serverPath]

        if (serverPath.isEmpty() || runningProcess == null) {
            result.error(
                "PROCESS_NOT_RUNNING",
                "No running server process was found for $serverPath.",
                null,
            )
            return
        }

        try {
            runningProcess.writer.write(command)
            runningProcess.writer.newLine()
            runningProcess.writer.flush()
            result.success(null)
        } catch (error: IOException) {
            result.error(
                "COMMAND_SEND_FAILED",
                error.message ?: "Unable to send a command to the server process.",
                null,
            )
        }
    }

    private fun stopProcess(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val serverPath = call.argument<String>("serverPath")?.trim().orEmpty()
        val runningProcess = runningProcesses[serverPath]

        if (serverPath.isEmpty() || runningProcess == null) {
            result.success(null)
            return
        }

        Thread {
            try {
                runningProcess.process.destroy()
                if (!runningProcess.process.waitFor(8, TimeUnit.SECONDS)) {
                    runningProcess.process.destroyForcibly()
                }
                cleanupProcess(serverPath)
                mainHandler.post {
                    result.success(null)
                }
            } catch (error: Exception) {
                cleanupProcess(serverPath)
                mainHandler.post {
                    result.error(
                        "PROCESS_STOP_FAILED",
                        error.message ?: "Unable to stop the Android server process.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun startStreamPump(
        serverPath: String,
        type: String,
        inputStream: InputStream,
    ): Thread {
        return Thread {
            BufferedReader(InputStreamReader(inputStream)).use { reader ->
                var line: String?
                while (true) {
                    line = reader.readLine() ?: break
                    emitProcessEvent(
                        type = type,
                        serverPath = serverPath,
                        message = line,
                    )
                }
            }
        }.apply { start() }
    }

    private fun emitProcessEvent(
        type: String,
        serverPath: String,
        message: String? = null,
        exitCode: Int? = null,
    ) {
        val payload = HashMap<String, Any?>()
        payload["type"] = type
        payload["serverPath"] = serverPath
        if (message != null) {
            payload["message"] = message
        }
        if (exitCode != null) {
            payload["exitCode"] = exitCode
        }

        mainHandler.post {
            processEventSink?.success(payload)
        }
    }

    private fun cleanupProcess(serverPath: String) {
        val runningProcess = runningProcesses.remove(serverPath) ?: return
        try {
            runningProcess.writer.close()
        } catch (_: IOException) {
        }
    }

    private fun resolveBundledJavaBinary(): File {
        return File(applicationInfo.nativeLibraryDir, "libbifrost_java.so")
    }

    private fun resolveBundledJavaHome(): File {
        return File(filesDir, "jre-home")
    }

    @Throws(IOException::class)
    private fun prepareBundledRuntimeHome() {
        val destinationRoot = resolveBundledJavaHome()
        copyAssetDirectory(
            assetPath = "jre-home",
            destinationDirectory = destinationRoot,
        )
    }

    @Throws(IOException::class)
    private fun copyAssetDirectory(
        assetPath: String,
        destinationDirectory: File,
    ) {
        val assetChildren = assets.list(assetPath) ?: emptyArray()

        if (assetChildren.isEmpty()) {
            destinationDirectory.parentFile?.mkdirs()
            assets.open(assetPath).use { inputStream ->
                BufferedInputStream(inputStream).use { bufferedInput ->
                    FileOutputStream(destinationDirectory).use { outputStream ->
                        bufferedInput.copyTo(outputStream)
                    }
                }
            }
            return
        }

        if (!destinationDirectory.exists()) {
            destinationDirectory.mkdirs()
        }

        for (child in assetChildren) {
            val childAssetPath = if (assetPath.isEmpty()) child else "$assetPath/$child"
            val childDestination = File(destinationDirectory, child)
            copyAssetDirectory(
                assetPath = childAssetPath,
                destinationDirectory = childDestination,
            )
        }
    }

    private fun configureJavaEnvironment(
        processBuilder: ProcessBuilder,
        executablePath: String,
    ) {
        val javaBinary = File(executablePath)
        val runtimeRoot = resolveBundledJavaHome()
        if (!runtimeRoot.exists()) {
            return
        }
        val libDirectory = File(runtimeRoot, "lib")

        val ldPaths = mutableListOf<String>()
        ldPaths.add(applicationInfo.nativeLibraryDir)
        if (libDirectory.exists()) {
            ldPaths.add(libDirectory.absolutePath)
        }

        processBuilder.environment()["BIFROST_JAVA_HOME"] = runtimeRoot.absolutePath
        processBuilder.environment()["JAVA_HOME"] = runtimeRoot.absolutePath
        processBuilder.environment()["LD_LIBRARY_PATH"] = ldPaths.joinToString(":")
        processBuilder.environment()["MEMTAG_OPTIONS"] = "off"
    }

    private fun getDocumentProviderPath(folderPath: String): String {
        if (folderPath.isEmpty()) {
            return "primary:recent"
        }

        val primaryPrefix = Environment.getExternalStorageDirectory().absolutePath
        val regex = Regex("^/storage/([A-Za-z0-9-]+)/?(.*)")

        return when {
            folderPath.startsWith(primaryPrefix) -> {
                "primary:${folderPath.removePrefix(primaryPrefix)}"
            }

            regex.matches(folderPath) -> {
                val matchResult = regex.find(folderPath)
                matchResult?.let {
                    val storageId = it.groups[1]?.value
                    val remainingPath = it.groups[2]?.value
                    "$storageId:${remainingPath}"
                } ?: "primary:$folderPath"
            }

            else -> {
                "primary:$folderPath"
            }
        }
    }

    @Throws(IOException::class)
    private fun runJavaSmokeTest(): Map<String, Any?> {
        val javaBinary = resolveBundledJavaBinary()
        val javaHome = resolveBundledJavaHome()

        if (!javaBinary.exists()) {
            throw IOException("Bundled Android JRE executable is missing at ${javaBinary.absolutePath}.")
        }

        if (!javaHome.exists()) {
            throw IOException("Bundled Android JRE home is missing at ${javaHome.absolutePath}.")
        }

        val processBuilder = ProcessBuilder(
            listOf(
                javaBinary.absolutePath,
                "-Djava.home=${javaHome.absolutePath}",
                "-version",
            ),
        )
        processBuilder.directory(filesDir)
        configureJavaEnvironment(
            processBuilder = processBuilder,
            executablePath = javaBinary.absolutePath,
        )
        processBuilder.redirectErrorStream(true)

        val process = processBuilder.start()
        val output = process.inputStream.bufferedReader().use { reader ->
            reader.readText()
        }.trim()
        val exitCode = process.waitFor()
        val libDirectory = File(javaHome, "lib")
        val serverLibDirectory = File(libDirectory, "server")
        val diagnostics = buildString {
            append("exitCode=")
            append(exitCode)
            append(", java=")
            append(javaBinary.absolutePath)
            append(" exists=")
            append(javaBinary.exists())
            append(", javaHome=")
            append(javaHome.absolutePath)
            append(" exists=")
            append(javaHome.exists())
            append(", libDir=")
            append(libDirectory.absolutePath)
            append(" exists=")
            append(libDirectory.exists())
            append(", serverLibDir=")
            append(serverLibDirectory.absolutePath)
            append(" exists=")
            append(serverLibDirectory.exists())
            append(", libjava=")
            append(File(libDirectory, "libjava.so").exists())
            append(", libjli=")
            append(File(libDirectory, "libjli.so").exists())
            append(", libjsig=")
            append(File(libDirectory, "libjsig.so").exists())
            append(", libjvm=")
            append(File(serverLibDirectory, "libjvm.so").exists())
            append(", modules=")
            append(File(libDirectory, "modules").exists())
            append(", LD_LIBRARY_PATH=")
            append(processBuilder.environment()["LD_LIBRARY_PATH"].orEmpty())
        }
        val finalOutput = if (output.isBlank()) diagnostics else "$output\n$diagnostics"

        return mapOf(
            "exitCode" to exitCode,
            "output" to finalOutput,
        )
    }

    private data class RunningServerProcess(
        val serverName: String,
        val process: Process,
        val writer: BufferedWriter,
        val stdoutThread: Thread,
        val stderrThread: Thread,
    )
}
