#include <android/log.h>
#include <dlfcn.h>
#include <errno.h>
#include <jni.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <dirent.h>

#include "log.h"
#include "utils.h"

/* ARM Memory Tagging / Tagged Pointers constants.
 * These may not be defined in older NDK headers. */
#ifndef M_BIONIC_SET_HEAP_TAGGING_LEVEL
#define M_BIONIC_SET_HEAP_TAGGING_LEVEL (-204)
#endif
#ifndef M_HEAP_TAGGING_LEVEL_NONE
#define M_HEAP_TAGGING_LEVEL_NONE 0
#endif

#define FULL_VERSION "21.0.0-internal"
#define DOT_VERSION "21"
#define PATH_BUFFER_SIZE 4096

typedef jint JLI_Launch_func(
    int argc,
    char** argv,
    int jargc,
    const char** jargv,
    int appclassc,
    const char** appclassv,
    const char* fullversion,
    const char* dotversion,
    const char* pname,
    const char* lname,
    jboolean javaargs,
    jboolean cpwildcard,
    jboolean javaw,
    jint ergo
);

static volatile sig_atomic_t active_jvm_pid = -1;
static volatile sig_atomic_t active_jvm_stdin_fd = -1;
static volatile sig_atomic_t active_jvm_ready = 0;

#define LOG_BUFFER_SIZE 262144
static pthread_mutex_t log_buffer_mutex = PTHREAD_MUTEX_INITIALIZER;
static char jvm_log_buffer[LOG_BUFFER_SIZE];
static size_t jvm_log_buffer_len = 0;
static uint64_t jvm_log_total_written = 0;

/* ──────────────────────────────────────────────────────────────────
 * Pipe-based log reader
 *
 * Reads from a pipe fd and forwards each line to Android logcat.
 * Used to capture the JVM child process's stdout/stderr.
 * ────────────────────────────────────────────────────────────────── */

static void inspect_jvm_log_line(const char* line) {
    if (line == NULL) {
        return;
    }

    if (strstr(line, "Done (") != NULL && strstr(line, "For help") != NULL) {
        active_jvm_ready = 1;
    }
}

static void append_jvm_log_line(const char* line) {
    if (line == NULL || line[0] == '\0') {
        return;
    }

    pthread_mutex_lock(&log_buffer_mutex);
    size_t line_len = strlen(line);
    size_t required = line_len + 1;
    if (required >= LOG_BUFFER_SIZE) {
        line += required - LOG_BUFFER_SIZE + 1;
        line_len = strlen(line);
        required = line_len + 1;
    }

    if (jvm_log_buffer_len + required >= LOG_BUFFER_SIZE) {
        size_t overflow = (jvm_log_buffer_len + required) - LOG_BUFFER_SIZE + 1;
        if (overflow < jvm_log_buffer_len) {
            memmove(jvm_log_buffer, jvm_log_buffer + overflow, jvm_log_buffer_len - overflow);
            jvm_log_buffer_len -= overflow;
        } else {
            jvm_log_buffer_len = 0;
        }
    }

    memcpy(jvm_log_buffer + jvm_log_buffer_len, line, line_len);
    jvm_log_buffer_len += line_len;
    jvm_log_buffer[jvm_log_buffer_len++] = '\n';
    jvm_log_buffer[jvm_log_buffer_len] = '\0';
    jvm_log_total_written += line_len + 1;
    pthread_mutex_unlock(&log_buffer_mutex);
}

static void* jvm_log_reader(void* arg) {
    int fd = *((int*) arg);
    free(arg);

    char buf[2048];
    ssize_t n;
    while ((n = read(fd, buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        char* line = buf;
        char* newline;
        while ((newline = strchr(line, '\n')) != NULL) {
            *newline = '\0';
            if (line[0] != '\0') {
                inspect_jvm_log_line(line);
                append_jvm_log_line(line);
                __android_log_print(ANDROID_LOG_INFO, "bifrost-jvm", "%s", line);
            }
            line = newline + 1;
        }
        if (line[0] != '\0') {
            inspect_jvm_log_line(line);
            append_jvm_log_line(line);
            __android_log_print(ANDROID_LOG_INFO, "bifrost-jvm", "%s", line);
        }
    }
    close(fd);
    return NULL;
}

static void start_log_reader(int read_fd) {
    int* fd_arg = malloc(sizeof(int));
    *fd_arg = read_fd;
    pthread_t thread;
    pthread_create(&thread, NULL, jvm_log_reader, fd_arg);
    pthread_detach(thread);
}

static const char* find_java_home_arg(int argc, char** argv) {
    const char* prefix = "-Djava.home=";
    size_t prefix_len = strlen(prefix);
    for (int i = 0; i < argc; i++) {
        if (argv[i] != NULL && strncmp(argv[i], prefix, prefix_len) == 0) {
            return argv[i] + prefix_len;
        }
    }
    return NULL;
}

static void* dlopen_runtime_library(int argc, char** argv, const char* relative_path) {
    const char* java_home = find_java_home_arg(argc, argv);
    if (java_home != NULL && java_home[0] != '\0') {
        char absolute_path[PATH_BUFFER_SIZE];
        snprintf(absolute_path, sizeof(absolute_path), "%s/%s", java_home, relative_path);
        void* handle = dlopen(absolute_path, RTLD_LAZY | RTLD_GLOBAL);
        if (handle != NULL) {
            return handle;
        }
        fprintf(stderr, "dlopen %s failed: %s\n", absolute_path, dlerror());
    }

    void* handle = dlopen(relative_path, RTLD_LAZY | RTLD_GLOBAL);
    if (handle != NULL) {
        return handle;
    }
    fprintf(stderr, "dlopen %s failed: %s\n", relative_path, dlerror());
    return NULL;
}

static bool runtime_library_exists(int argc, char** argv, const char* relative_path) {
    const char* java_home = find_java_home_arg(argc, argv);
    if (java_home == NULL || java_home[0] == '\0') {
        return false;
    }

    char absolute_path[PATH_BUFFER_SIZE];
    snprintf(absolute_path, sizeof(absolute_path), "%s/%s", java_home, relative_path);
    return access(absolute_path, R_OK) == 0;
}

static void preload_library_from_path_list(const char* library_name) {
    const char* path_list = getenv("LD_LIBRARY_PATH");
    if (path_list == NULL || path_list[0] == '\0') {
        return;
    }

    char* mutable_paths = strdup(path_list);
    if (mutable_paths == NULL) {
        return;
    }

    char* save_ptr = NULL;
    char* directory = strtok_r(mutable_paths, ":", &save_ptr);
    while (directory != NULL) {
        char absolute_path[PATH_BUFFER_SIZE];
        snprintf(absolute_path, sizeof(absolute_path), "%s/%s", directory, library_name);
        if (access(absolute_path, R_OK) == 0) {
            void* handle = dlopen(absolute_path, RTLD_NOW | RTLD_GLOBAL);
            if (handle != NULL) {
                fprintf(stdout, "Preloaded %s\n", absolute_path);
                free(mutable_paths);
                return;
            }
            fprintf(stderr, "Preload %s failed: %s\n", absolute_path, dlerror());
        }
        directory = strtok_r(NULL, ":", &save_ptr);
    }

    free(mutable_paths);
}

static void preload_runtime_core_libraries(int argc, char** argv) {
    const char* modern_core_libraries[] = {
        "lib/server/libjvm.so",
        "lib/libjava.so",
        "lib/libverify.so",
        "lib/libnet.so",
        "lib/libnio.so",
        "lib/libzip.so",
        "lib/libjimage.so",
        NULL
    };
    const char* java8_core_libraries[] = {
        "lib/aarch64/server/libjvm.so",
        "lib/aarch64/libjava.so",
        "lib/aarch64/libverify.so",
        "lib/aarch64/libnet.so",
        "lib/aarch64/libnio.so",
        "lib/aarch64/libzip.so",
        NULL
    };

    if (runtime_library_exists(argc, argv, "lib/libjava.so")) {
        for (int i = 0; modern_core_libraries[i] != NULL; i++) {
            dlopen_runtime_library(argc, argv, modern_core_libraries[i]);
        }
        return;
    }

    if (runtime_library_exists(argc, argv, "lib/aarch64/libjava.so")) {
        for (int i = 0; java8_core_libraries[i] != NULL; i++) {
            dlopen_runtime_library(argc, argv, java8_core_libraries[i]);
        }
    }
}

/* ──────────────────────────────────────────────────────────────────
 * LD_LIBRARY_PATH sanitizer
 *
 * Removes system GPU library directories (/system/lib*, /vendor/lib*)
 * from LD_LIBRARY_PATH. On Qualcomm Adreno devices the OpenGL driver
 * (libGLESv2_adreno.so) crashes with SIGSEGV when loaded outside a
 * proper EGL/display context, which a headless forked JVM child
 * does not have. Since the Minecraft server is headless, no GPU
 * access is needed — stripping these paths is safe.
 * ────────────────────────────────────────────────────────────────── */

static void sanitize_ld_library_path(void) {
    const char* current = getenv("LD_LIBRARY_PATH");
    if (current == NULL || current[0] == '\0') {
        return;
    }

    char* mutable_copy = strdup(current);
    if (mutable_copy == NULL) {
        return;
    }

    char sanitized[PATH_BUFFER_SIZE];
    sanitized[0] = '\0';
    size_t sanitized_len = 0;

    char* save_ptr = NULL;
    char* segment = strtok_r(mutable_copy, ":", &save_ptr);
    while (segment != NULL) {
        /* Skip any path under /system/lib or /vendor/lib */
        if (strncmp(segment, "/system/lib", 11) != 0 &&
            strncmp(segment, "/vendor/lib", 11) != 0) {
            size_t seg_len = strlen(segment);
            if (sanitized_len + seg_len + 2 < PATH_BUFFER_SIZE) {
                if (sanitized_len > 0) {
                    sanitized[sanitized_len++] = ':';
                }
                memcpy(sanitized + sanitized_len, segment, seg_len);
                sanitized_len += seg_len;
                sanitized[sanitized_len] = '\0';
            }
        }
        segment = strtok_r(NULL, ":", &save_ptr);
    }

    free(mutable_copy);
    setenv("LD_LIBRARY_PATH", sanitized, 1);
    fprintf(stdout, "Sanitized LD_LIBRARY_PATH (GPU libs removed)\n");
}

/* ──────────────────────────────────────────────────────────────────
 * GPU device file descriptor cleanup
 *
 * After fork(), the child inherits all of the parent's open file
 * descriptors, including GPU device files like /dev/kgsl-3d0
 * (Qualcomm Adreno). The Adreno driver's internal state was
 * initialized in the parent and is invalid in the child — when
 * driver code tries to use these stale FDs, it crashes with SIGSEGV.
 *
 * Closing these FDs prevents the driver from talking to the GPU
 * hardware. Any driver cleanup code will get EBADF instead of
 * accessing invalid GPU state.
 * ────────────────────────────────────────────────────────────────── */

static void close_gpu_device_fds(void) {
    DIR* proc_fd_dir = opendir("/proc/self/fd");
    if (proc_fd_dir == NULL) {
        return;
    }

    int dir_fd = dirfd(proc_fd_dir);
    struct dirent* entry;

    while ((entry = readdir(proc_fd_dir)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }

        int fd = atoi(entry->d_name);
        /* Never close stdin/stdout/stderr or the directory fd itself. */
        if (fd <= STDERR_FILENO || fd == dir_fd) {
            continue;
        }

        char link_path[128];
        char target[512];
        snprintf(link_path, sizeof(link_path), "/proc/self/fd/%d", fd);
        ssize_t len = readlink(link_path, target, sizeof(target) - 1);
        if (len <= 0) {
            continue;
        }
        target[len] = '\0';

        /* Close GPU device files:
         *   /dev/kgsl-*  — Qualcomm Adreno
         *   /dev/mali*   — ARM Mali
         *   /dev/pvr*    — PowerVR / Imagination
         *   /dev/dri/*   — DRM (generic)
         *   /dev/ion     — ION memory allocator (used by GPU) */
        if (strncmp(target, "/dev/kgsl", 9) == 0 ||
            strncmp(target, "/dev/mali", 9) == 0 ||
            strncmp(target, "/dev/pvr", 8) == 0 ||
            strncmp(target, "/dev/dri/", 9) == 0 ||
            strcmp(target, "/dev/ion") == 0) {
            close(fd);
            fprintf(stdout, "Closed GPU device fd %d -> %s\n", fd, target);
        }
    }

    closedir(proc_fd_dir);
}

/* ──────────────────────────────────────────────────────────────────
 * GPU library memory unmapping
 *
 * Removes the Adreno/OpenGL driver code from the child's address
 * space entirely by reading /proc/self/maps and munmapping all
 * regions belonging to GPU-related libraries. After this, any
 * accidental call into the driver hits unmapped memory — the
 * JVM's own SIGSEGV handler catches it cleanly instead of the
 * driver crashing internally with corrupt state.
 * ────────────────────────────────────────────────────────────────── */

static void unmap_gpu_libraries(void) {
    FILE* maps = fopen("/proc/self/maps", "r");
    if (maps == NULL) {
        return;
    }

    char line[1024];
    int unmapped_count = 0;

    while (fgets(line, sizeof(line), maps) != NULL) {
        /* Only unmap GPU-related libraries. */
        if (strstr(line, "libGLES") == NULL &&
            strstr(line, "libEGL") == NULL &&
            strstr(line, "adreno") == NULL &&
            strstr(line, "vulkan") == NULL &&
            strstr(line, "libgsl") == NULL) {
            continue;
        }

        /* Parse the address range: "start-end perms ..." */
        unsigned long start = 0, end = 0;
        if (sscanf(line, "%lx-%lx", &start, &end) != 2) {
            continue;
        }
        if (start == 0 || end <= start) {
            continue;
        }

        size_t length = end - start;
        if (munmap((void*) start, length) == 0) {
            unmapped_count++;
        }
    }

    fclose(maps);
    if (unmapped_count > 0) {
        fprintf(stdout, "Unmapped %d GPU library regions from child process\n",
                unmapped_count);
    }
}

/* ──────────────────────────────────────────────────────────────────
 * JVM launch (runs inside the forked child process)
 * ────────────────────────────────────────────────────────────────── */

static jint launch_jvm_child(int argc, char** argv) {
    /* Disable ARM heap pointer tagging (MTE/TBI) in this process.
     * The JVM's native code truncates the top-byte tag from pointers,
     * which causes SIGABRT on Android 12+ if tagging is enabled.
     * We call mallopt via dlsym since it may not be in our NDK headers. */
    typedef int (*mallopt_func)(int, int);
    mallopt_func mallopt_p = (mallopt_func) dlsym(RTLD_DEFAULT, "mallopt");
    if (mallopt_p != NULL) {
        if (mallopt_p(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE) != 0) {
            fprintf(stdout, "Heap pointer tagging disabled\n");
        } else {
            fprintf(stderr, "Warning: mallopt failed to disable heap tagging\n");
        }
    } else {
        fprintf(stdout, "mallopt not available, heap tagging unchanged\n");
    }

    /* Reset all signal handlers for a clean JVM slate */
    struct sigaction clean_sa;
    memset(&clean_sa, 0, sizeof(struct sigaction));
    for (int sigid = SIGHUP; sigid < NSIG; sigid++) {
        clean_sa.sa_handler = sigid == SIGSEGV ? SIG_IGN : SIG_DFL;
        sigaction(sigid, &clean_sa, NULL);
    }

    preload_library_from_path_list("libc++_shared.so");

    void* libjli = dlopen_runtime_library(argc, argv, "lib/libjli.so");
    if (libjli == NULL) {
        libjli = dlopen_runtime_library(argc, argv, "lib/aarch64/jli/libjli.so");
    }
    if (libjli == NULL) {
        fprintf(stderr, "JLI lib = NULL\n");
        return -1;
    }

    preload_runtime_core_libraries(argc, argv);

    JLI_Launch_func* jliLaunch = (JLI_Launch_func*) dlsym(libjli, "JLI_Launch");
    if (jliLaunch == NULL) {
        fprintf(stderr, "JLI_Launch symbol not found\n");
        return -1;
    }

    fprintf(stdout, "Calling JLI_Launch (pid=%d)\n", getpid());
    fflush(stdout);

    jint result = jliLaunch(
        argc,
        argv,
        0,
        NULL,
        0,
        NULL,
        FULL_VERSION,
        DOT_VERSION,
        *argv,
        *argv,
        JNI_FALSE,
        JNI_TRUE,
        JNI_FALSE,
        0
    );

    fprintf(stdout, "JLI_Launch returned %d\n", result);
    fflush(stdout);
    return result;
}

/* ──────────────────────────────────────────────────────────────────
 * JNI entry point
 *
 * Strategy: fork() a child process to run the JVM. If the JVM
 * calls exit() or crashes, only the child dies. The parent
 * (Flutter app) survives and gets the exit code via waitpid().
 * ────────────────────────────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_launchJVM(
    JNIEnv* env,
    jclass clazz,
    jobjectArray argsArray
) {
    (void) clazz;
    if (argsArray == NULL) {
        LOGE("Args array null, returning");
        return 0;
    }

    int argc = (*env)->GetArrayLength(env, argsArray);
    char** jni_argv = convert_to_char_array(env, argsArray);

    /* Deep-copy the argument strings so they remain valid after
     * we release the JNI references and across the fork boundary. */
    char** argv = (char**) malloc(argc * sizeof(char*));
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup(jni_argv[i]);
    }
    free_char_array(env, argsArray, (const char**) jni_argv);

    LOGD("launchJVM: argc=%d", argc);
    for (int i = 0; i < argc; i++) {
        LOGD("  argv[%d]=%s", i, argv[i]);
    }

    /* Create pipes for child stdin and stdout/stderr */
    int input_pipe[2];
    if (pipe(input_pipe) != 0) {
        LOGE("stdin pipe() failed: %s", strerror(errno));
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return -1;
    }

    int output_pipe[2];
    if (pipe(output_pipe) != 0) {
        LOGE("stdout pipe() failed: %s", strerror(errno));
        close(input_pipe[0]);
        close(input_pipe[1]);
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return -1;
    }

    LOGD("Forking child process for JVM");
    active_jvm_ready = 0;
    pthread_mutex_lock(&log_buffer_mutex);
    jvm_log_buffer_len = 0;
    jvm_log_buffer[0] = '\0';
    pthread_mutex_unlock(&log_buffer_mutex);
    pid_t pid = fork();

    if (pid < 0) {
        LOGE("fork() failed: %s", strerror(errno));
        close(input_pipe[0]);
        close(input_pipe[1]);
        close(output_pipe[0]);
        close(output_pipe[1]);
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return -1;
    }

    if (pid == 0) {
        /* ───── CHILD PROCESS ─────
         *
         * Set parent-death signal so that this child process is automatically
         * terminated when the parent Flutter process is killed.
         */
        prctl(PR_SET_PDEATHSIG, SIGKILL);

        /*
         * GPU driver isolation for Android:
         *
         * The Flutter parent uses OpenGL (via Skia) for rendering,
         * so libGLESv2_adreno.so is loaded in its address space with
         * open GPU device FDs (/dev/kgsl-3d0 on Qualcomm).
         *
         * fork() copies those mapped GPU driver pages and FDs to the
         * child. The Adreno driver is NOT fork-safe — if any JVM
         * shutdown code accidentally touches those pages, the driver's
         * internal state is invalid and it crashes with SIGSEGV.
         *
         * We apply 3 layers of defense:
         * 1. Close GPU device FDs (/dev/kgsl-*) so the driver can't
         *    talk to hardware and gets EBADF on any ioctl.
         * 2. munmap GPU library pages so driver code can't execute.
         * 3. Strip GPU paths from LD_LIBRARY_PATH to prevent reloading.
         *
         * Pipe redirections (stdin/stdout/stderr) survive because
         * dup2'd standard FDs are not close-on-exec by default.
         */
        close(input_pipe[1]); /* close stdin write end */
        close(output_pipe[0]); /* close read end */

        dup2(input_pipe[0], STDIN_FILENO);
        close(input_pipe[0]);

        /* Redirect stdout and stderr to the pipe */
        dup2(output_pipe[1], STDOUT_FILENO);
        dup2(output_pipe[1], STDERR_FILENO);
        close(output_pipe[1]);

        setvbuf(stdout, NULL, _IOLBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);

        /* ── GPU driver isolation ──
         *
         * The Flutter parent uses OpenGL (Skia), so the Adreno driver
         * (libGLESv2_adreno.so) is loaded and has open device FDs
         * (/dev/kgsl-3d0). fork() copies all of this to the child.
         *
         * The driver is NOT fork-safe — its internal GPU state is
         * invalid in the child. During JVM shutdown, cleanup code
         * touches the driver and crashes with SIGSEGV.
         *
         * Fix: 2 layers of defense:
         * 1. Close GPU device FDs so the driver can't ioctl hardware
         * 2. Strip GPU paths from LD_LIBRARY_PATH to prevent reloading
         *
         * We do NOT munmap the GPU library pages because the JVM and
         * other loaded libraries retain function pointers/vtable entries
         * pointing into those regions. Unmapping causes an immediate
         * SIGSEGV at startup from dangling pointers.
         *
         * The residual shutdown crash (after all world data is saved)
         * is cosmetic — the parent handles signal-killed children
         * gracefully via the stopRequested/exitCode logic. */
        close_gpu_device_fds();
        sanitize_ld_library_path();

        jint result = launch_jvm_child(argc, argv);

        _exit(result);
    }

    /* ───── PARENT PROCESS ───── */
    close(input_pipe[0]); /* close child stdin read end */
    close(output_pipe[1]); /* close write end */

    /* Start a background thread to read the child's output and
     * forward it to logcat under the "bifrost-jvm" tag. */
    start_log_reader(output_pipe[0]);

    LOGD("Waiting for JVM child process (pid=%d)", pid);
    active_jvm_pid = pid;
    active_jvm_stdin_fd = input_pipe[1];

    int status = 0;
    waitpid(pid, &status, 0);
    active_jvm_pid = -1;
    active_jvm_ready = 0;
    if (active_jvm_stdin_fd >= 0) {
        close((int) active_jvm_stdin_fd);
        active_jvm_stdin_fd = -1;
    }

    jint exit_code;
    if (WIFEXITED(status)) {
        exit_code = (jint) WEXITSTATUS(status);
        LOGD("JVM child exited normally with code %d", exit_code);
    } else if (WIFSIGNALED(status)) {
        int sig = WTERMSIG(status);
        exit_code = (jint) (128 + sig);
        LOGE("JVM child killed by signal %d", sig);
    } else {
        exit_code = -1;
        LOGE("JVM child ended with unknown status 0x%x", status);
    }

    /* Clean up deep-copied args */
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);

    return exit_code;
}

JNIEXPORT jboolean JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_isJVMReady(
    JNIEnv* env,
    jclass clazz
) {
    (void) env;
    (void) clazz;
    return active_jvm_ready == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_getJVMPid(
    JNIEnv* env,
    jclass clazz
) {
    (void) env;
    (void) clazz;
    return (jint) active_jvm_pid;
}

JNIEXPORT jstring JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_getJVMOutput(
    JNIEnv* env,
    jclass clazz
) {
    (void) clazz;
    pthread_mutex_lock(&log_buffer_mutex);
    jstring output = (*env)->NewStringUTF(env, jvm_log_buffer);
    pthread_mutex_unlock(&log_buffer_mutex);
    return output;
}

JNIEXPORT jobjectArray JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_getJVMOutputIncremental(
    JNIEnv* env,
    jclass clazz,
    jlong lastTotalRead
) {
    (void) clazz;
    pthread_mutex_lock(&log_buffer_mutex);

    // If buffer length is 0, reset total written counter (e.g. on JVM restart)
    if (jvm_log_buffer_len == 0) {
        jvm_log_total_written = 0;
    }

    jboolean reset_buffer = JNI_FALSE;
    uint64_t bytes_to_send = 0;

    // Validate bounds to prevent unsigned underflow
    if (lastTotalRead < 0 || lastTotalRead > (jlong)jvm_log_total_written) {
        reset_buffer = JNI_TRUE;
    } else {
        bytes_to_send = jvm_log_total_written - (uint64_t)lastTotalRead;
        if (bytes_to_send > jvm_log_buffer_len) {
            reset_buffer = JNI_TRUE;
        }
    }

    jstring output_string;
    if (reset_buffer == JNI_TRUE) {
        output_string = (*env)->NewStringUTF(env, jvm_log_buffer);
    } else {
        const char* start_ptr = jvm_log_buffer + (jvm_log_buffer_len - bytes_to_send);
        output_string = (*env)->NewStringUTF(env, start_ptr);
    }

    // Wrap outputs in Object[] of size 3:
    // [0]: String output
    // [1]: java.lang.Long total_written
    // [2]: java.lang.Boolean reset

    jclass obj_class = (*env)->FindClass(env, "java/lang/Object");
    jobjectArray result_array = (*env)->NewObjectArray(env, 3, obj_class, NULL);

    // Box Long
    jclass long_class = (*env)->FindClass(env, "java/lang/Long");
    jmethodID long_value_of = (*env)->GetStaticMethodID(env, long_class, "valueOf", "(J)Ljava/lang/Long;");
    jobject boxed_long = (*env)->CallStaticObjectMethod(env, long_class, long_value_of, (jlong)jvm_log_total_written);

    // Box Boolean
    jclass bool_class = (*env)->FindClass(env, "java/lang/Boolean");
    jmethodID bool_value_of = (*env)->GetStaticMethodID(env, bool_class, "valueOf", "(Z)Ljava/lang/Boolean;");
    jobject boxed_bool = (*env)->CallStaticObjectMethod(env, bool_class, bool_value_of, reset_buffer);

    (*env)->SetObjectArrayElement(env, result_array, 0, output_string);
    (*env)->SetObjectArrayElement(env, result_array, 1, boxed_long);
    (*env)->SetObjectArrayElement(env, result_array, 2, boxed_bool);

    pthread_mutex_unlock(&log_buffer_mutex);

    return result_array;
}

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_stopJVM(
    JNIEnv* env,
    jclass clazz
) {
    (void) env;
    (void) clazz;

    int fd = (int) active_jvm_stdin_fd;
    if (fd < 0) {
        LOGD("stopJVM requested but no active JVM stdin pipe is registered");
        return 0;
    }

    const char* command = "stop\n";
    ssize_t written = write(fd, command, strlen(command));
    if (written < 0) {
        LOGE("Writing graceful stop command failed: %s", strerror(errno));
        return -1;
    }

    LOGD("Graceful stop command written to JVM child stdin");
    return 1;
}

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_sendJVMCommand(
    JNIEnv* env,
    jclass clazz,
    jstring commandString
) {
    (void) clazz;

    int fd = (int) active_jvm_stdin_fd;
    if (fd < 0) {
        LOGD("sendJVMCommand requested but no active JVM stdin pipe is registered");
        return 0;
    }

    const char* command = (*env)->GetStringUTFChars(env, commandString, NULL);
    if (command == NULL) {
        return -1;
    }

    size_t command_len = strlen(command);
    ssize_t written = write(fd, command, command_len);
    if (written >= 0 && (command_len == 0 || command[command_len - 1] != '\n')) {
        ssize_t newline_written = write(fd, "\n", 1);
        if (newline_written < 0) {
            written = -1;
        }
    }

    if (written < 0) {
        LOGE("Writing JVM command failed: %s", strerror(errno));
        (*env)->ReleaseStringUTFChars(env, commandString, command);
        return -1;
    }

    char echo_line[1024];
    snprintf(echo_line, sizeof(echo_line), "> %s", command);
    append_jvm_log_line(echo_line);
    LOGD("JVM command written to child stdin");
    (*env)->ReleaseStringUTFChars(env, commandString, command);
    return 1;
}

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_terminateJVM(
    JNIEnv* env,
    jclass clazz
) {
    (void) env;
    (void) clazz;

    pid_t pid = (pid_t) active_jvm_pid;
    if (pid <= 0) {
        LOGD("terminateJVM requested but no active JVM child is registered");
        return 0;
    }

    if (kill(pid, SIGTERM) != 0) {
        LOGE("SIGTERM failed for JVM child pid=%d: %s", pid, strerror(errno));
        return -1;
    }

    LOGD("SIGTERM sent to JVM child pid=%d", pid);
    return 1;
}

JNIEXPORT jint JNICALL
Java_com_arcadelabs_bifrost_LocalJvmBridge_forceStopJVM(
    JNIEnv* env,
    jclass clazz
) {
    (void) env;
    (void) clazz;

    pid_t pid = (pid_t) active_jvm_pid;
    if (pid <= 0) {
        LOGD("forceStopJVM requested but no active JVM child is registered");
        return 0;
    }

    if (kill(pid, SIGKILL) != 0) {
        LOGE("SIGKILL failed for JVM child pid=%d: %s", pid, strerror(errno));
        return -1;
    }

    LOGD("SIGKILL sent to JVM child pid=%d", pid);
    return 1;
}
