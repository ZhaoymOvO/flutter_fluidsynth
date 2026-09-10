package com.ffs.ffs

import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "FluidSynthLoader"

        init {
            val libs = listOf(
                "c++_shared",
                "ogg",
                "opus",
                "FLAC",
                "vorbis",
                "vorbisenc",
                "vorbisfile",
                "sndfile",
                "oboe",
                "fluidsynth-assetloader",
                "fluidsynth"
            )
            for (lib in libs) {
                try {
                    System.loadLibrary(lib)
                    Log.i(TAG, "Pre-loaded native library: $lib")
                } catch (t: Throwable) {
                    Log.w(TAG, "Optional pre-load for $lib skipped: ${t.message}")
                }
            }
        }
    }
}
