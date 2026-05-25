package com.yourname.bifrost

object LocalJvmBridge {
    init {
        System.loadLibrary("bifrost_jre_launcher")
    }

    external fun launchJVM(args: Array<String>): Int

    external fun stopJVM(): Int

    external fun sendJVMCommand(command: String): Int

    external fun terminateJVM(): Int

    external fun forceStopJVM(): Int

    external fun isJVMReady(): Boolean

    external fun getJVMPid(): Int

    external fun getJVMOutput(): String

    external fun setLdLibraryPath(ldLibraryPath: String)

    external fun dlopen(name: String): Boolean

    external fun chdir(path: String): Int
}
