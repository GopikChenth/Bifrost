package com.arcadelabs.bifrost

import org.tukaani.xz.XZInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

object TarXzExtractor {
    private const val blockSize = 512

    fun extract(input: InputStream, destination: File) {
        XZInputStream(BufferedInputStream(input)).use { xzInput ->
            val header = ByteArray(blockSize)
            while (true) {
                if (!readFully(xzInput, header)) {
                    return
                }
                if (header.all { it.toInt() == 0 }) {
                    return
                }

                val name = parseString(header, 0, 100)
                if (name.isBlank()) {
                    return
                }
                val prefix = parseString(header, 345, 155)
                val entryName = normalizeEntryName(
                    if (prefix.isBlank()) name else "$prefix/$name",
                )
                val size = parseOctal(header, 124, 12)
                val typeFlag = header[156].toInt().toChar()
                val outputFile = File(destination, entryName).canonicalFile
                val root = destination.canonicalFile
                if (!outputFile.path.startsWith(root.path)) {
                    throw IOException("Refusing to extract outside runtime directory: $entryName")
                }

                when (typeFlag) {
                    '5' -> {
                        if (!outputFile.exists() && !outputFile.mkdirs()) {
                            throw IOException("Unable to create directory ${outputFile.absolutePath}")
                        }
                    }
                    '0', '\u0000' -> {
                        outputFile.parentFile?.mkdirs()
                        outputFile.outputStream().use { output ->
                            copyExactly(xzInput, output, size)
                        }
                    }
                    else -> {
                        skipExactly(xzInput, size)
                    }
                }

                val padding = (blockSize - (size % blockSize)) % blockSize
                if (padding > 0) {
                    skipExactly(xzInput, padding)
                }
            }
        }
    }

    private fun normalizeEntryName(rawName: String): String {
        return rawName
            .replace('\\', '/')
            .removePrefix("./")
            .trimStart('/')
    }

    private fun parseString(buffer: ByteArray, offset: Int, length: Int): String {
        var end = offset
        val max = offset + length
        while (end < max && buffer[end].toInt() != 0) {
            end++
        }
        return buffer.copyOfRange(offset, end).toString(Charsets.UTF_8).trim()
    }

    private fun parseOctal(buffer: ByteArray, offset: Int, length: Int): Long {
        val value = parseString(buffer, offset, length).trim()
        if (value.isBlank()) {
            return 0L
        }
        return value.toLong(8)
    }

    private fun readFully(input: InputStream, buffer: ByteArray): Boolean {
        var read = 0
        while (read < buffer.size) {
            val count = input.read(buffer, read, buffer.size - read)
            if (count < 0) {
                if (read == 0) {
                    return false
                }
                throw IOException("Unexpected end of tar header.")
            }
            read += count
        }
        return true
    }

    private fun copyExactly(input: InputStream, output: java.io.OutputStream, bytes: Long) {
        var remaining = bytes
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (remaining > 0) {
            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (count < 0) {
                throw IOException("Unexpected end of tar entry.")
            }
            output.write(buffer, 0, count)
            remaining -= count
        }
    }

    private fun skipExactly(input: InputStream, bytes: Long) {
        var remaining = bytes
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
                continue
            }
            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (count < 0) {
                throw IOException("Unexpected end of tar padding.")
            }
            remaining -= count
        }
    }
}
