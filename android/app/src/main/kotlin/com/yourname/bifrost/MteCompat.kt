package com.yourname.bifrost

/**
 * Disables Android Memory Tagging Extension (MTE) and heap pointer tagging
 * at the native level. Call [disable] once early in the app lifecycle,
 * before any child processes are spawned via ProcessBuilder.
 *
 * This is required because:
 * - android:allowNativeHeapPointerTagging="false" only affects the app's own Zygote process
 * - android:memtagMode="off" may not be respected on all devices/API levels
 * - Child processes spawned via ProcessBuilder inherit the parent's mallopt state via fork()
 * - The JVM's native memory management conflicts with ARM MTE pointer tagging
 */
object MteCompat {
    private var disabled = false

    init {
        try {
            System.loadLibrary("bifrost_mte")
        } catch (_: UnsatisfiedLinkError) {
            // Library not available on this architecture — nothing to do.
        }
    }

    /**
     * Disables heap tagging and tagged address checks for this process.
     * Safe to call multiple times; only the first call has effect.
     * Must be called on the main thread before any ProcessBuilder usage.
     */
    fun disable() {
        if (disabled) return
        try {
            nativeDisableMemoryTagging()
            disabled = true
        } catch (_: UnsatisfiedLinkError) {
            // Not available — device may not need it.
        }
    }

    private external fun nativeDisableMemoryTagging()
}
