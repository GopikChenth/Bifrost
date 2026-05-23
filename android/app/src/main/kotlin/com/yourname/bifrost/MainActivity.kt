package com.yourname.bifrost

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.widget.RemoteViews

class MainActivity : FlutterActivity() {
    private val localRuntimeManager: LocalRuntimeManager by lazy {
        LocalRuntimeManager(this)
    }
    private val storageAccessManager: StorageAccessManager by lazy {
        StorageAccessManager(this)
    }

    private val CHANNEL_ID = "bifrost_server_status"
    private val NOTIFICATION_ID = 4554
    private val ACTION_START = "com.yourname.bifrost.ACTION_START"
    private val ACTION_STOP = "com.yourname.bifrost.ACTION_STOP"

    private var lastNotificationName: String? = null
    private var lastNotificationType: String? = null
    private var lastNotificationVersion: String? = null
    private lateinit var channel: MethodChannel
    private var receiver: BroadcastReceiver? = null

    override fun onDestroy() {
        receiver?.let {
            unregisterReceiver(it)
        }
        super.onDestroy()
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

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bifrost/local_runtime",
        )
        channel.setMethodCallHandler(::handleLocalRuntimeMethodCall)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_START)
            addAction(ACTION_STOP)
        }

        val dynamicReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    ACTION_STOP -> {
                        try {
                            localRuntimeManager.stopServer()
                            showOrUpdateNotification(
                                name = lastNotificationName ?: "Server",
                                type = lastNotificationType ?: "",
                                version = lastNotificationVersion ?: "",
                                status = "Stopping"
                            )
                            channel.invokeMethod("stopServerFromNotification", null)
                        } catch (e: Exception) {
                            Log.e("Bifrost", "Failed to stop server from notification", e)
                        }
                    }
                    ACTION_START -> {
                        channel.invokeMethod("startServerFromNotification", null)
                    }
                }
            }
        }
        receiver = dynamicReceiver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dynamicReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dynamicReceiver, filter)
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

    private fun handleStorageAccessMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "hasAllFilesAccess" -> {
                    result.success(storageAccessManager.hasAllFilesAccess())
                }
                "requestAllFilesAccess" -> {
                    storageAccessManager.requestAllFilesAccess()
                    result.success(null)
                }
                "getDefaultExternalBasePath" -> {
                    result.success(storageAccessManager.getDefaultExternalBasePath())
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(
                "STORAGE_ACCESS_FAILED",
                error.localizedMessage ?: "Storage access operation failed.",
                null,
            )
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
                    val runtimeMajor = call.argument<Int>("runtimeMajor") ?: 21
                    localRuntimeManager.prepareBundledRuntimeHome(runtimeMajor)
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
                    val runtimeMajor = call.argument<Int>("runtimeMajor") ?: 21
                    val exitCode = localRuntimeManager.runJavaVersion(
                        workingDirectory = workingDirectory,
                        runtimeMajor = runtimeMajor,
                    )
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
                    val runtimeMajor = call.argument<Int>("runtimeMajor") ?: 21

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
                            runtimeMajor = runtimeMajor,
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

            "updateNotification" -> {
                val name = call.argument<String>("name").orEmpty()
                val type = call.argument<String>("type").orEmpty()
                val version = call.argument<String>("version").orEmpty()
                val status = call.argument<String>("status").orEmpty()
                showOrUpdateNotification(name, type, version, status)
                result.success(null)
            }

            "cancelNotification" -> {
                cancelNotification()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Server Status"
            val descriptionText = "Displays status and control actions for your server"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showOrUpdateNotification(name: String, type: String, version: String, status: String) {
        lastNotificationName = name
        lastNotificationType = type
        lastNotificationVersion = version

        createNotificationChannel()

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(ACTION_STOP).apply {
            `package` = packageName
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val startIntent = Intent(ACTION_START).apply {
            `package` = packageName
        }
        val startPendingIntent = PendingIntent.getBroadcast(
            this,
            2,
            startIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isOngoing = status.equals("running", ignoreCase = true) ||
                        status.equals("starting", ignoreCase = true) ||
                        status.equals("stopping", ignoreCase = true)

        val remoteViews = RemoteViews(packageName, R.layout.notification_custom).apply {
            setTextViewText(R.id.txt_title, "Server: $name")
            setTextViewText(R.id.txt_subtitle, "$type $version • $status")
            setTextViewText(R.id.btn_action, if (isOngoing) "Stop" else "Start")
            setInt(
                R.id.btn_action,
                "setBackgroundResource",
                if (isOngoing) R.drawable.notification_button_stop else R.drawable.notification_button_start
            )
            setOnClickPendingIntent(
                R.id.btn_action,
                if (isOngoing) stopPendingIntent else startPendingIntent
            )
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setCustomContentView(remoteViews)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setOngoing(isOngoing)
            .setAutoCancel(!isOngoing)

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun cancelNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
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
