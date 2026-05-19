package com.yourname.bifrost

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity

/**
 * Manages external storage access using MANAGE_EXTERNAL_STORAGE.
 *
 * All server files live on the direct filesystem
 * (e.g. /storage/emulated/0/Bifrost/minecraft/) — no SAF, no
 * content:// URIs, no DocumentFile.  The permission survives
 * reboots and never silently expires.
 */
class StorageAccessManager(
    private val activity: FlutterActivity,
) {
    /**
     * Returns `true` when the app has MANAGE_EXTERNAL_STORAGE
     * (or the device is below API 30, where it's not needed).
     */
    fun hasAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    /**
     * Opens the system settings page where the user can grant
     * "All files access" to this app.
     */
    fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            activity.startActivity(intent)
        }
    }

    /**
     * Returns the default external base directory for Bifrost server
     * files — `/storage/emulated/0/Bifrost`.
     */
    fun getDefaultExternalBasePath(): String {
        return java.io.File(
            Environment.getExternalStorageDirectory(),
            "Bifrost",
        ).absolutePath
    }
}
