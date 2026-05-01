#include <jni.h>
#include <sys/prctl.h>

// PR_SET_TAGGED_ADDR_CTRL may not be in older NDK headers.
#ifndef PR_SET_TAGGED_ADDR_CTRL
#define PR_SET_TAGGED_ADDR_CTRL 55
#endif

// MTE tag check fault mode: none (disable checks).
#ifndef PR_MTE_TCF_NONE
#define PR_MTE_TCF_NONE 0
#endif

/**
 * Disables Android's Memory Tagging Extension (MTE) and heap pointer tagging
 * for the current process. This must be called before spawning child processes
 * via ProcessBuilder so that the child inherits the disabled state via fork().
 *
 * This uses prctl(PR_SET_TAGGED_ADDR_CTRL, 0) to disable tagged address checks
 * in the kernel for the current process. Errors are ignored because not all
 * kernels expose the control.
 */
JNIEXPORT void JNICALL
Java_com_yourname_bifrost_MteCompat_nativeDisableMemoryTagging(
    JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;

    // Disable kernel tagged address ABI and MTE tag check faults.
    // Errors are ignored because not all kernels support this.
    prctl(PR_SET_TAGGED_ADDR_CTRL, PR_MTE_TCF_NONE, 0, 0, 0);
}
