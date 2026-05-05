package com.yourname.bifrost

import android.content.Intent
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localRuntimeManager: LocalRuntimeManager by lazy {
        LocalRuntimeManager(this)
    }
    private val storageAccessManager: StorageAccessManager by lazy {
        StorageAccessManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/storage_access",
        ).setMethodCallHandler(::handleStorageAccessMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/file_manager",
        ).setMethodCallHandler(::handleFileManagerMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/local_runtime",
        ).setMethodCallHandler(::handleLocalRuntimeMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/native_package",
        ).setMethodCallHandler(::handleNativePackageMethodCall)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (storageAccessManager.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handleNativePackageMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
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

    @Suppress("UNCHECKED_CAST")
    private fun handleStorageAccessMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "pickDirectory" -> storageAccessManager.pickDirectory(result)
                "createServerStructure" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.createServerStructure(arguments)
                }
                "loadStoredServers" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.loadStoredServers(arguments)
                }
                "copyFileToDirectory" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.copyFileToDirectory(arguments)
                }
                "writeDownloadMetadata" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.writeDownloadMetadata(arguments)
                    null
                }
                "deleteServerDirectory" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.deleteServerDirectory(arguments)
                    null
                }
                "prepareServerLaunch" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.prepareServerLaunch(arguments)
                }
                "copyServerToDirectory" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.copyServerToDirectory(arguments)
                }
                "syncDirectoryToServer" -> runStorageOperation(
                    call = call,
                    result = result,
                ) { arguments ->
                    storageAccessManager.syncDirectoryToServer(arguments)
                    null
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            val message = buildString {
                append(call.method)
                append(" failed: ")
                append(error::class.java.simpleName)
                val details = error.message ?: error.localizedMessage
                if (!details.isNullOrBlank()) {
                    append(": ")
                    append(details)
                }
            }
            result.error(
                "STORAGE_ACCESS_FAILED",
                message,
                null,
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun runStorageOperation(
        call: MethodCall,
        result: MethodChannel.Result,
        operation: (Map<String, Any?>) -> Any?,
    ) {
        Thread {
            try {
                val operationResult = operation(call.arguments as? Map<String, Any?> ?: emptyMap())
                runOnUiThread {
                    result.success(operationResult)
                }
            } catch (error: Exception) {
                val message = buildString {
                    append(call.method)
                    append(" failed: ")
                    append(error::class.java.simpleName)
                    val details = error.message ?: error.localizedMessage
                    if (!details.isNullOrBlank()) {
                        append(": ")
                        append(details)
                    }
                }
                runOnUiThread {
                    result.error("STORAGE_ACCESS_FAILED", message, null)
                }
            }
        }.apply {
            name = "bifrost-storage-${call.method}"
            start()
        }
    }

    private fun handleLocalRuntimeMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getRuntimeStatus" -> {
                try {
                    result.success(localRuntimeManager.getRuntimeStatus())
                } catch (error: Exception) {
                    result.error(
                        "RUNTIME_STATUS_FAILED",
                        error.localizedMessage ?: "Unable to inspect the runtime state.",
                        null,
                    )
                }
            }

            "prepareBundledRuntimeHome" -> {
                try {
                    localRuntimeManager.prepareBundledRuntimeHome()
                    result.success(localRuntimeManager.getRuntimeStatus())
                } catch (error: Exception) {
                    result.error(
                        "PREPARE_RUNTIME_FAILED",
                        error.localizedMessage ?: "Unable to prepare the bundled runtime.",
                        null,
                    )
                }
            }

            "runJavaVersion" -> {
                try {
                    val workingDirectory = call.argument<String>("workingDirectory")
                    val exitCode = localRuntimeManager.runJavaVersion(workingDirectory)
                    result.success(
                        mapOf(
                            "exitCode" to exitCode,
                            "runtimeStatus" to localRuntimeManager.getRuntimeStatus(),
                        ),
                    )
                } catch (error: Exception) {
                    result.error(
                        "RUN_JAVA_VERSION_FAILED",
                        error.localizedMessage ?: "Unable to run the bundled JVM.",
                        null,
                    )
                }
            }

            "getServerStatus" -> {
                try {
                    result.success(localRuntimeManager.getServerStatus())
                } catch (error: Exception) {
                    result.error(
                        "SERVER_STATUS_FAILED",
                        error.localizedMessage ?: "Unable to inspect the local server status.",
                        null,
                    )
                }
            }

            "startServer" -> {
                try {
                    val serverPath = call.argument<String>("serverPath")?.trim().orEmpty()
                    val jarPath = call.argument<String>("jarPath")?.trim().orEmpty()
                    val maxRamMb = call.argument<Int>("maxRamMb") ?: 2048

                    if (serverPath.isEmpty() || jarPath.isEmpty()) {
                        result.error(
                            "INVALID_SERVER_LAUNCH",
                            "serverPath and jarPath are required.",
                            null,
                        )
                        return
                    }

                    result.success(
                        localRuntimeManager.startServer(
                            serverPath = serverPath,
                            jarPath = jarPath,
                            maxRamMb = maxRamMb,
                        ),
                    )
                } catch (error: Exception) {
                    result.error(
                        "START_SERVER_FAILED",
                        error.localizedMessage ?: "Unable to start the local server.",
                        null,
                    )
                }
            }

            "stopServer" -> {
                try {
                    result.success(localRuntimeManager.stopServer())
                } catch (error: Exception) {
                    result.error(
                        "STOP_SERVER_FAILED",
                        error.localizedMessage ?: "Unable to stop the local server.",
                        null,
                    )
                }
            }

            "sendServerCommand" -> {
                try {
                    val command = call.argument<String>("command")?.trim().orEmpty()
                    if (command.isEmpty()) {
                        result.error(
                            "INVALID_SERVER_COMMAND",
                            "command is required.",
                            null,
                        )
                        return
                    }

                    result.success(localRuntimeManager.sendServerCommand(command))
                } catch (error: Exception) {
                    result.error(
                        "SEND_SERVER_COMMAND_FAILED",
                        error.localizedMessage ?: "Unable to send the server command.",
                        null,
                    )
                }
            }

            else -> result.notImplemented()
        }
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
}
