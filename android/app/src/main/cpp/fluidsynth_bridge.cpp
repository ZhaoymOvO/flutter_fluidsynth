#include <jni.h>

// Bridge ensuring libc++_shared.so is bundled by Android NDK
extern "C" JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void* reserved) {
    return JNI_VERSION_1_6;
}
