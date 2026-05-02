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
#include <sys/wait.h>
#include <unistd.h>

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

/* ──────────────────────────────────────────────────────────────────
 * Pipe-based log reader
 *
 * Reads from a pipe fd and forwards each line to Android logcat.
 * Used to capture the JVM child process's stdout/stderr.
 * ────────────────────────────────────────────────────────────────── */

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
                __android_log_print(ANDROID_LOG_INFO, "bifrost-jvm", "%s", line);
            }
            line = newline + 1;
        }
        if (line[0] != '\0') {
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

    void* libjli = dlopen("libjli.so", RTLD_LAZY | RTLD_GLOBAL);
    if (libjli == NULL) {
        fprintf(stderr, "JLI lib = NULL: %s\n", dlerror());
        return -1;
    }

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
Java_com_yourname_bifrost_LocalJvmBridge_launchJVM(
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

    /* Create a pipe to capture the child's stdout + stderr */
    int output_pipe[2];
    if (pipe(output_pipe) != 0) {
        LOGE("pipe() failed: %s", strerror(errno));
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return -1;
    }

    LOGD("Forking child process for JVM");
    pid_t pid = fork();

    if (pid < 0) {
        LOGE("fork() failed: %s", strerror(errno));
        close(output_pipe[0]);
        close(output_pipe[1]);
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
        return -1;
    }

    if (pid == 0) {
        /* ───── CHILD PROCESS ───── */
        close(output_pipe[0]); /* close read end */

        /* Redirect stdout and stderr to the pipe */
        dup2(output_pipe[1], STDOUT_FILENO);
        dup2(output_pipe[1], STDERR_FILENO);
        close(output_pipe[1]);

        setvbuf(stdout, NULL, _IOLBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);

        jint result = launch_jvm_child(argc, argv);

        /* If JLI_Launch actually returns (rare), exit with its code.
         * Normally the JVM calls exit() internally and we never
         * reach here — but that's fine, the parent catches it. */
        _exit(result);
    }

    /* ───── PARENT PROCESS ───── */
    close(output_pipe[1]); /* close write end */

    /* Start a background thread to read the child's output and
     * forward it to logcat under the "bifrost-jvm" tag. */
    start_log_reader(output_pipe[0]);

    LOGD("Waiting for JVM child process (pid=%d)", pid);

    int status = 0;
    waitpid(pid, &status, 0);

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
