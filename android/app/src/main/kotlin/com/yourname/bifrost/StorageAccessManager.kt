package com.yourname.bifrost

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.IOException

class StorageAccessManager(
    private val activity: FlutterActivity,
) {
    companion object {
        private const val REQUEST_OPEN_DOCUMENT_TREE = 4107
    }

    private val contentResolver: ContentResolver
        get() = activity.contentResolver

    private var pendingPickResult: MethodChannel.Result? = null

    fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("DIRECTORY_PICK_IN_PROGRESS", "A directory pick is already active.", null)
            return
        }

        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_OPEN_DOCUMENT_TREE)
    }

    fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_OPEN_DOCUMENT_TREE) {
            return false
        }

        val result = pendingPickResult
        pendingPickResult = null

        if (result == null) {
            return true
        }

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return true
        }

        val flags =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        contentResolver.takePersistableUriPermission(uri, flags)
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "path" to (resolveTreePath(uri) ?: uri.toString()),
            ),
        )
        return true
    }

    fun createServerStructure(arguments: Map<String, Any?>): Map<String, Any?> {
        val treeUri = requireString(arguments, "treeUri")
        val serverName = requireString(arguments, "serverName")
        val version = requireString(arguments, "version")
        val serverType = requireString(arguments, "serverType")
        val memoryLabel = requireString(arguments, "memoryLabel")
        val serverProperties = requireString(arguments, "serverProperties")

        val root = requireTree(treeUri)
        val minecraftDir = findOrCreateDirectory(root, "minecraft")
        val serverSlug = createUniqueServerSlug(minecraftDir, slugify(serverName))
        val serverDir = requireNotNull(minecraftDir.createDirectory(serverSlug)) {
            "Unable to create server directory."
        }

        val worldDir = findOrCreateDirectory(serverDir, "world")
        val jarsDir = findOrCreateDirectory(serverDir, "jars")
        val modsDir = findOrCreateDirectory(serverDir, "mods")
        val backupsDir = findOrCreateDirectory(serverDir, "backups")

        val propertiesFile = createOrReplaceTextFile(serverDir, "server.properties", serverProperties)
        val metadataFile = createOrReplaceTextFile(
            serverDir,
            "bifrost_server.json",
            buildMetadataJson(
                serverName = serverName,
                version = version,
                serverType = serverType,
                memoryLabel = memoryLabel,
                serverDir = serverDir,
                worldDir = worldDir,
                jarsDir = jarsDir,
                modsDir = modsDir,
                backupsDir = backupsDir,
                propertiesFile = propertiesFile,
                treeUri = treeUri,
                serverSlug = serverSlug,
            ),
        )

        val serverRawPath = resolveTreePath(Uri.parse(treeUri))?.let {
            File(it, "minecraft/$serverSlug").absolutePath
        }

        return mapOf(
            "serverPath" to (serverRawPath ?: serverDir.uri.toString()),
            "worldPath" to (joinRaw(serverRawPath, "world") ?: worldDir.uri.toString()),
            "jarsPath" to (joinRaw(serverRawPath, "jars") ?: jarsDir.uri.toString()),
            "modsPath" to (joinRaw(serverRawPath, "mods") ?: modsDir.uri.toString()),
            "backupsPath" to (joinRaw(serverRawPath, "backups") ?: backupsDir.uri.toString()),
            "propertiesPath" to
                (joinRaw(serverRawPath, "server.properties") ?: propertiesFile.uri.toString()),
            "metadataPath" to
                (joinRaw(serverRawPath, "bifrost_server.json") ?: metadataFile.uri.toString()),
            "serverUri" to serverDir.uri.toString(),
            "jarsUri" to jarsDir.uri.toString(),
            "metadataUri" to metadataFile.uri.toString(),
        )
    }

    fun loadStoredServers(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val treeUri = requireString(arguments, "treeUri")
        val root = requireTree(treeUri)
        val minecraftDir = root.findFile("minecraft") ?: return emptyList()

        val servers = mutableListOf<Map<String, Any?>>()
        for (serverDir: DocumentFile in minecraftDir.listFiles()) {
            if (!serverDir.isDirectory) {
                continue
            }

            val metadataFile = serverDir.findFile("bifrost_server.json") ?: continue
            try {
                val metadata = JSONObject(readText(metadataFile.uri))
                val paths = metadata.optJSONObject("paths")
                val uris = metadata.optJSONObject("uris")

                servers.add(
                    mapOf(
                        "name" to metadata.optString("name", serverDir.name ?: "Unknown"),
                        "version" to metadata.optString("version", "Unknown"),
                        "type" to metadata.optString("type", "Unknown"),
                        "memory" to metadata.optString("allocatedRam", "2.0 GB"),
                        "path" to (
                            paths?.optString("root")?.takeUnless { it.isBlank() }
                                ?: serverDir.uri.toString()
                        ),
                        "serverUri" to (
                            uris?.optString("root")?.takeUnless { it.isBlank() }
                                ?: serverDir.uri.toString()
                        ),
                        "metadataUri" to metadataFile.uri.toString(),
                        "jarsUri" to (
                            uris?.optString("jars")?.takeUnless { it.isBlank() }
                                ?: serverDir.findFile("jars")?.uri?.toString()
                        ),
                    ),
                )
            } catch (_: Throwable) {
                continue
            }
        }

        return servers.sortedBy { (it["name"] as? String).orEmpty().lowercase() }
    }

    fun copyFileToDirectory(arguments: Map<String, Any?>): Map<String, Any?> {
        val directoryUri = requireString(arguments, "directoryUri")
        val fileName = requireString(arguments, "fileName")
        val sourcePath = requireString(arguments, "sourcePath")

        val sourceFile = File(sourcePath)
        if (!sourceFile.isFile) {
            throw IOException("Downloaded file is missing at $sourcePath.")
        }

        val directory = requireDirectoryDocument(directoryUri)
        directory.findFile(fileName)?.delete()
        val targetFile = createBinaryFile(directory, fileName)
        var copiedBytes = 0L

        contentResolver.openOutputStream(targetFile.uri, "w")!!.use { output ->
            sourceFile.inputStream().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) {
                        break
                    }
                    output.write(buffer, 0, read)
                    copiedBytes += read
                }
                output.flush()
            }
        }

        val directoryRawPath = resolveDocumentPath(directory.uri)
        return mapOf(
            "path" to (
                directoryRawPath?.let { File(it, fileName).absolutePath }
                    ?: targetFile.uri.toString()
            ),
            "copiedBytes" to copiedBytes,
        )
    }

    fun syncDirectoryToServer(arguments: Map<String, Any?>) {
        val serverUri = requireString(arguments, "serverUri")
        val sourcePath = requireString(arguments, "sourcePath")
        val sourceDir = File(sourcePath)
        if (!sourceDir.isDirectory) {
            throw IOException("Runtime mirror is missing at $sourcePath.")
        }

        val serverDir = requireDirectoryDocument(serverUri)
        for (child: DocumentFile in serverDir.listFiles()) {
            deleteRecursively(child)
        }
        sourceDir.listFiles().orEmpty().forEach { child ->
            copyFileTreeToDocument(child, serverDir)
        }
    }

    fun writeDownloadMetadata(arguments: Map<String, Any?>) {
        val metadataUri = requireString(arguments, "metadataUri")
        val metadataFile = requireDocument(metadataUri)
        val downloadMetadata = arguments["downloadMetadata"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val current = JSONObject(readText(metadataFile.uri))
        current.put("download", JSONObject(downloadMetadata))
        writeText(metadataFile.uri, current.toString(2))
    }

    fun deleteServerDirectory(arguments: Map<String, Any?>) {
        val treeUri = requireString(arguments, "treeUri")
        val serverUri = (arguments["serverUri"] as? String)?.trim().orEmpty()
        val serverPath = (arguments["serverPath"] as? String)?.trim().orEmpty()

        if (serverUri.isNotEmpty()) {
            try {
                val serverDir = requireDirectoryDocument(serverUri)
                if (deleteRecursively(serverDir)) {
                    return
                }
            } catch (_: Throwable) {
                // Fall back to lookup by name under the selected tree.
            }
        }

        val root = requireTree(treeUri)
        val minecraftDir = root.findFile("minecraft")
            ?: throw IOException("minecraft directory is missing in the selected storage tree.")
        val serverFolderName = serverPath.substringAfterLast('/').substringAfterLast('\\').trim()
        if (serverFolderName.isEmpty()) {
            throw IOException("Unable to determine the server folder name for deletion.")
        }

        val serverDir = minecraftDir.findFile(serverFolderName)
            ?: throw IOException("Unable to find $serverFolderName in the selected storage tree.")
        if (!deleteRecursively(serverDir)) {
            throw IOException("Unable to delete ${serverDir.name ?: serverFolderName}.")
        }
    }

    fun prepareServerLaunch(arguments: Map<String, Any?>): Map<String, Any?> {
        val serverUri = requireString(arguments, "serverUri")
        val serverDir = requireDirectoryDocument(serverUri)
        val metadataFile = serverDir.findFile("bifrost_server.json")
            ?: throw IOException("bifrost_server.json is missing for this server.")

        val metadata = JSONObject(readText(metadataFile.uri))
        val download = metadata.optJSONObject("download")
            ?: throw IOException("No downloaded server jar is registered for this server yet.")
        val jarPath = download.optString("path")
        if (jarPath.isBlank()) {
            throw IOException("No downloaded server jar is registered for this server yet.")
        }

        val eulaFile = createOrReplaceTextFile(serverDir, "eula.txt", "eula=true\n")
        val paths = metadata.optJSONObject("paths")
        return mapOf(
            "serverPath" to (
                paths?.optString("root")?.takeUnless { it.isBlank() }
                    ?: resolveDocumentPath(serverDir.uri)
                    ?: serverDir.uri.toString()
            ),
            "jarPath" to jarPath,
            "metadataUri" to metadataFile.uri.toString(),
            "eulaUri" to eulaFile.uri.toString(),
        )
    }

    fun copyServerToDirectory(arguments: Map<String, Any?>): Map<String, Any?> {
        val serverUri = requireString(arguments, "serverUri")
        val destinationPath = requireString(arguments, "destinationPath")
        val serverDir = requireDirectoryDocument(serverUri)
        val destinationDir = File(destinationPath)

        if (destinationDir.exists()) {
            destinationDir.deleteRecursively()
        }
        if (!destinationDir.mkdirs() && !destinationDir.isDirectory) {
            throw IOException("Unable to create runtime mirror at $destinationPath.")
        }

        copyDocumentTree(serverDir, destinationDir)

        val metadataFile = File(destinationDir, "bifrost_server.json")
        if (!metadataFile.isFile) {
            throw IOException("bifrost_server.json is missing after copying the server.")
        }

        val metadata = JSONObject(metadataFile.readText())
        val download = metadata.optJSONObject("download")
            ?: throw IOException("No downloaded server jar is registered for this server yet.")
        val fileName = download.optString("fileName", "server.jar")
        val jarsDir = File(destinationDir, "jars")
        val jarFile = File(jarsDir, fileName).takeIf { it.isFile }
            ?: jarsDir.listFiles()?.firstOrNull {
                it.isFile && it.name.endsWith(".jar", ignoreCase = true)
            }
        if (jarFile == null || !jarFile.isFile) {
            throw IOException("The copied server jar is missing in ${jarsDir.absolutePath}.")
        }

        File(destinationDir, "eula.txt").writeText("eula=true\n")

        return mapOf(
            "serverPath" to destinationDir.absolutePath,
            "jarPath" to jarFile.absolutePath,
            "metadataPath" to metadataFile.absolutePath,
        )
    }

    private fun buildMetadataJson(
        serverName: String,
        version: String,
        serverType: String,
        memoryLabel: String,
        serverDir: DocumentFile,
        worldDir: DocumentFile,
        jarsDir: DocumentFile,
        modsDir: DocumentFile,
        backupsDir: DocumentFile,
        propertiesFile: DocumentFile,
        treeUri: String,
        serverSlug: String,
    ): String {
        val serverRawPath = resolveTreePath(Uri.parse(treeUri))?.let {
            File(it, "minecraft/$serverSlug").absolutePath
        }
        val root = JSONObject()
        root.put("name", serverName)
        root.put("version", version)
        root.put("type", serverType)
        root.put("allocatedRam", memoryLabel)
        root.put("download", JSONObject.NULL)

        val paths = JSONObject()
        paths.put("root", serverRawPath ?: "")
        paths.put("world", joinRaw(serverRawPath, "world") ?: "")
        paths.put("jars", joinRaw(serverRawPath, "jars") ?: "")
        paths.put("mods", joinRaw(serverRawPath, "mods") ?: "")
        paths.put("backups", joinRaw(serverRawPath, "backups") ?: "")
        paths.put("properties", joinRaw(serverRawPath, "server.properties") ?: "")
        root.put("paths", paths)

        val uris = JSONObject()
        uris.put("root", serverDir.uri.toString())
        uris.put("world", worldDir.uri.toString())
        uris.put("jars", jarsDir.uri.toString())
        uris.put("mods", modsDir.uri.toString())
        uris.put("backups", backupsDir.uri.toString())
        uris.put("properties", propertiesFile.uri.toString())
        root.put("uris", uris)
        return root.toString(2)
    }

    private fun requireTree(treeUri: String): DocumentFile {
        return requireNotNull(DocumentFile.fromTreeUri(activity, Uri.parse(treeUri))) {
            "Selected storage directory is no longer available."
        }
    }

    private fun requireDocument(documentUri: String): DocumentFile {
        return requireNotNull(DocumentFile.fromSingleUri(activity, Uri.parse(documentUri))) {
            "Requested storage document is no longer available."
        }
    }

    private fun requireDirectoryDocument(documentUri: String): DocumentFile {
        val uri = Uri.parse(documentUri)
        val directory = try {
            val authority = uri.authority ?: return requireDocument(documentUri)
            val treeId = DocumentsContract.getTreeDocumentId(uri)
            val documentId = DocumentsContract.getDocumentId(uri)
            val rootTreeUri = DocumentsContract.buildTreeDocumentUri(authority, treeId)
            val root = DocumentFile.fromTreeUri(activity, rootTreeUri)
                ?: return requireDocument(documentUri)

            if (documentId == treeId) {
                root
            } else {
                val relativePath = documentId
                    .removePrefix(treeId)
                    .removePrefix("/")
                relativePath
                    .split('/')
                    .filter { it.isNotBlank() }
                    .fold(root as DocumentFile?) { current, segment ->
                        current?.findFile(segment)
                    }
            }
        } catch (_: IllegalArgumentException) {
            DocumentFile.fromTreeUri(activity, uri)
        }

        return requireNotNull(directory) {
            "Requested storage directory is no longer available."
        }
    }

    private fun requireString(arguments: Map<String, Any?>, key: String): String {
        val value = (arguments[key] as? String)?.trim().orEmpty()
        require(value.isNotEmpty()) { "$key is required." }
        return value
    }

    private fun findOrCreateDirectory(parent: DocumentFile, name: String): DocumentFile {
        return parent.findFile(name)
            ?: requireNotNull(parent.createDirectory(name)) {
                "Unable to create directory $name."
            }
    }

    private fun createOrReplaceTextFile(
        parent: DocumentFile,
        name: String,
        contents: String,
    ): DocumentFile {
        parent.findFile(name)?.delete()
        val mimeType = if (name.endsWith(".json")) "application/json" else "text/plain"
        val file = requireNotNull(parent.createFile(mimeType, name)) {
            "Unable to create file $name."
        }
        writeText(file.uri, contents)
        return file
    }

    private fun createBinaryFile(parent: DocumentFile, name: String): DocumentFile {
        val createdFile = try {
            parent.createFile("application/octet-stream", name)
        } catch (error: Throwable) {
            throw IOException("Unable to create destination file $name: ${error.message}", error)
        }

        return requireNotNull(createdFile) {
            "Unable to create destination file $name in ${parent.name ?: parent.uri}."
        }
    }

    private fun writeText(uri: Uri, contents: String) {
        contentResolver.openOutputStream(uri, "w")!!.bufferedWriter().use { writer ->
            writer.write(contents)
            writer.flush()
        }
    }

    private fun readText(uri: Uri): String {
        return contentResolver.openInputStream(uri)!!.bufferedReader().use { reader ->
            reader.readText()
        }
    }

    private fun deleteRecursively(document: DocumentFile): Boolean {
        if (document.isDirectory) {
            for (child: DocumentFile in document.listFiles()) {
                deleteRecursively(child)
            }
        }
        return document.delete()
    }

    private fun copyDocumentTree(source: DocumentFile, destination: File) {
        if (source.isDirectory) {
            if (!destination.exists() && !destination.mkdirs()) {
                throw IOException("Unable to create directory ${destination.absolutePath}.")
            }
            for (child: DocumentFile in source.listFiles()) {
                val childName = child.name ?: continue
                copyDocumentTree(child, File(destination, childName))
            }
            return
        }

        destination.parentFile?.mkdirs()
        contentResolver.openInputStream(source.uri)!!.use { input ->
            destination.outputStream().use { output ->
                input.copyTo(output)
                output.flush()
            }
        }
    }

    private fun copyFileTreeToDocument(source: File, destination: DocumentFile) {
        if (source.isDirectory) {
            val targetDirectory = findOrCreateDirectory(destination, source.name)
            source.listFiles().orEmpty().forEach { child ->
                copyFileTreeToDocument(child, targetDirectory)
            }
            return
        }

        destination.findFile(source.name)?.delete()
        val targetFile = createBinaryFile(destination, source.name)
        contentResolver.openOutputStream(targetFile.uri, "w")!!.use { output ->
            source.inputStream().use { input ->
                input.copyTo(output)
                output.flush()
            }
        }
    }

    private fun createUniqueServerSlug(parent: DocumentFile, baseSlug: String): String {
        var candidate = baseSlug
        var suffix = 2
        while (parent.findFile(candidate) != null) {
            candidate = "$baseSlug-$suffix"
            suffix++
        }
        return candidate
    }

    private fun slugify(input: String): String {
        val cleaned = input
            .trim()
            .lowercase()
            .replace(Regex("[^a-z0-9]+"), "-")
            .replace(Regex("^-+|-+$"), "")
        return if (cleaned.isBlank()) "server" else cleaned
    }

    private fun resolveTreePath(uri: Uri): String? {
        return resolveDocumentIdPath(DocumentsContract.getTreeDocumentId(uri))
    }

    private fun resolveDocumentPath(uri: Uri): String? {
        return try {
            resolveDocumentIdPath(DocumentsContract.getDocumentId(uri))
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun resolveDocumentIdPath(documentId: String?): String? {
        if (documentId.isNullOrBlank()) {
            return null
        }
        val parts = documentId.split(':', limit = 2)
        if (parts.isEmpty()) {
            return null
        }

        val volume = parts[0]
        val relative = parts.getOrNull(1).orEmpty()
        val base = if (volume == "primary") {
            Environment.getExternalStorageDirectory().absolutePath
        } else {
            "/storage/$volume"
        }
        return if (relative.isBlank()) base else File(base, relative).absolutePath
    }

    private fun joinRaw(base: String?, child: String): String? {
        if (base.isNullOrBlank()) {
            return null
        }
        return File(base, child).absolutePath
    }
}
