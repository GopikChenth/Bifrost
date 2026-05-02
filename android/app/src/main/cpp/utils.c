#include <dlfcn.h>
#include <jni.h>
#include <stdlib.h>
#include <unistd.h>

#include "log.h"
#include "utils.h"

typedef void (*android_update_LD_LIBRARY_PATH_t)(char*);

char** convert_to_char_array(JNIEnv* env, jobjectArray jstringArray) {
    int numRows = (*env)->GetArrayLength(env, jstringArray);
    char** cArray = (char**) malloc(numRows * sizeof(char*));

    for (int i = 0; i < numRows; i++) {
        jstring row = (jstring) (*env)->GetObjectArrayElement(env, jstringArray, i);
        cArray[i] = (char*) (*env)->GetStringUTFChars(env, row, 0);
    }

    return cArray;
}

void free_char_array(JNIEnv* env, jobjectArray jstringArray, const char** charArray) {
    int numRows = (*env)->GetArrayLength(env, jstringArray);

    for (int i = 0; i < numRows; i++) {
        jstring row = (jstring) (*env)->GetObjectArrayElement(env, jstringArray, i);
        (*env)->ReleaseStringUTFChars(env, row, charArray[i]);
    }
}

JNIEXPORT void JNICALL
Java_com_yourname_bifrost_LocalJvmBridge_setLdLibraryPath(
    JNIEnv* env,
    jclass clazz,
    jstring ldLibraryPath
) {
    void* libdlHandle = dlopen("libdl.so", RTLD_LAZY);
    void* updateLdLibPath = dlsym(libdlHandle, "android_update_LD_LIBRARY_PATH");
    if (updateLdLibPath == NULL) {
        updateLdLibPath = dlsym(libdlHandle, "__loader_android_update_LD_LIBRARY_PATH");
    }
    if (updateLdLibPath == NULL) {
        LOGE("android_update_LD_LIBRARY_PATH not found: %s", dlerror());
        return;
    }

    android_update_LD_LIBRARY_PATH_t androidUpdateLdLibraryPath =
        (android_update_LD_LIBRARY_PATH_t) updateLdLibPath;
    const char* ldLibPathUtf = (*env)->GetStringUTFChars(env, ldLibraryPath, 0);
    androidUpdateLdLibraryPath((char*) ldLibPathUtf);
    (*env)->ReleaseStringUTFChars(env, ldLibraryPath, ldLibPathUtf);
}

JNIEXPORT jboolean JNICALL
Java_com_yourname_bifrost_LocalJvmBridge_dlopen(
    JNIEnv* env,
    jclass clazz,
    jstring name
) {
    const char* nameUtf = (*env)->GetStringUTFChars(env, name, 0);
    void* handle = dlopen(nameUtf, RTLD_GLOBAL | RTLD_LAZY);
    if (!handle) {
        LOGE("dlopen %s failed: %s", nameUtf, dlerror());
    } else {
        LOGD("dlopen %s success", nameUtf);
    }
    (*env)->ReleaseStringUTFChars(env, name, nameUtf);
    return handle != NULL;
}

JNIEXPORT jint JNICALL
Java_com_yourname_bifrost_LocalJvmBridge_chdir(
    JNIEnv* env,
    jclass clazz,
    jstring nameStr
) {
    const char* name = (*env)->GetStringUTFChars(env, nameStr, NULL);
    int retval = chdir(name);
    (*env)->ReleaseStringUTFChars(env, nameStr, name);
    return retval;
}
