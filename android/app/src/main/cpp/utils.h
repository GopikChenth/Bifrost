#pragma once

#include <jni.h>

char** convert_to_char_array(JNIEnv* env, jobjectArray jstringArray);
void free_char_array(JNIEnv* env, jobjectArray jstringArray, const char** charArray);
