package com.yourname.bifrost

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicReference

class TunnelManager(
    private val context: Context,
) {
    private val tag = "bifrost-tunnel"

    // Android package manager extracts jniLibs/*.so to nativeLibraryDir,
    // which is on an executable partition. We ship bore as libbore.so so
    // it lands here automatically — no manual copy needed.
    private val boreFile: File
        get() = File(context.applicationInfo.nativeLibraryDir, "libbore.so")

    private val tunnelState = AtomicReference("idle")
    private val remotePort = AtomicReference<Int?>(null)
    private val lastMessage = AtomicReference<String?>(null)

    @Volatile
    private var tunnelProcess: Process? = null

    @Volatile
    private var tunnelThread: Thread? = null

    // ── Tunnel lifecycle ──────────────────────────────────────────────────────

    @Synchronized
    fun startTunnel(localPort: Int): Map<String, Any?> {
        val existingThread = tunnelThread
        if (existingThread != null && existingThread.isAlive) {
            return getTunnelStatus()
        }

        val bore = boreFile
        if (!bore.exists()) {
            tunnelState.set("error")
            lastMessage.set(
                "bore binary not found at ${bore.absolutePath}. " +
                    "Ensure libbore.so is in src/main/jniLibs/arm64-v8a/.",
            )
            Log.e(tag, "bore binary missing: ${bore.absolutePath}")
            return getTunnelStatus()
        }

        tunnelState.set("starting")
        remotePort.set(null)
        lastMessage.set("Connecting to bore.pub\u2026")

        val thread = Thread {
            try {
                Log.d(tag, "Launching: ${bore.absolutePath} local $localPort --to bore.pub")

                val process = ProcessBuilder(
                    bore.absolutePath,
                    "local",
                    localPort.toString(),
                    "--to",
                    "bore.pub",
                )
                    .redirectErrorStream(true)
                    .start()

                tunnelProcess = process

                val outputLines = mutableListOf<String>()

                // Read stdout line by line to detect the assigned port
                process.inputStream.bufferedReader().use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        val currentLine = line ?: continue
                        Log.d(tag, "bore: $currentLine")
                        outputLines.add(currentLine)
                        parseListeningPort(currentLine)?.let { port ->
                            remotePort.set(port)
                            tunnelState.set("active")
                            lastMessage.set("Tunnel active at bore.pub:$port")
                            Log.d(tag, "Tunnel active at bore.pub:$port")
                        }
                    }
                }

                val exitCode = process.waitFor()
                Log.d(tag, "bore exited with code $exitCode")

                // Build a meaningful message from bore's own output
                val boreOutput = outputLines.takeLast(3).joinToString(" | ").trim()
                val baseMessage = if (exitCode == 0) "Tunnel stopped." else "Tunnel exited (code $exitCode)."
                val fullMessage = if (boreOutput.isNotEmpty()) "$baseMessage bore: $boreOutput" else baseMessage

                if (tunnelState.get() != "stopping") {
                    tunnelState.set(if (exitCode == 0) "stopped" else "error")
                    lastMessage.set(fullMessage)
                } else {
                    tunnelState.set("stopped")
                    lastMessage.set("Tunnel stopped.")
                }
            } catch (error: Throwable) {
                tunnelState.set("error")
                lastMessage.set(error.localizedMessage ?: "Tunnel launch failed.")
                Log.e(tag, "Tunnel error", error)
            } finally {
                tunnelProcess = null
                tunnelThread = null
                remotePort.set(null)
            }
        }
        thread.name = "bifrost-bore-tunnel"
        tunnelThread = thread
        thread.start()

        return getTunnelStatus()
    }

    @Synchronized
    fun stopTunnel(): Map<String, Any?> {
        val process = tunnelProcess
        if (process == null) {
            tunnelState.set("stopped")
            lastMessage.set("No active tunnel to stop.")
            remotePort.set(null)
            return getTunnelStatus()
        }

        tunnelState.set("stopping")
        lastMessage.set("Stopping bore tunnel\u2026")
        process.destroy()
        Log.d(tag, "bore process destroyed")
        return getTunnelStatus()
    }

    fun getTunnelStatus(): Map<String, Any?> {
        return mapOf(
            "state" to tunnelState.get(),
            "remotePort" to remotePort.get(),
            "message" to lastMessage.get(),
        )
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun parseListeningPort(line: String): Int? {
        // bore outputs: "listening at bore.pub:38291"
        val prefix = "listening at bore.pub:"
        val index = line.indexOf(prefix)
        if (index == -1) return null
        return line.substring(index + prefix.length).trim().toIntOrNull()
    }
}
