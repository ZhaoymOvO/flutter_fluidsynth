package io.github.zhaoymovo.ffs

import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val TAG = "FluidSynthLoader"

        /**
         * Keep the media notification icon out of the resource shrinker's reach.
         *
         * audio_service resolves the notification icon by *name* at runtime
         * (`Resources.getIdentifier(config.androidNotificationIcon, ...)`), and
         * the name is configured from Dart. The release build's resource
         * shrinker scans bytecode and XML for references, cannot see a Dart
         * string, and therefore strips the drawable:
         *
         *     @io.github.zhaoymovo.ffs:drawable/ic_stat_synthbox : reachable=false
         *
         * getIdentifier() then returns 0, audio_service calls setSmallIcon(0),
         * and NotificationCompat.Builder.build() throws — so no notification is
         * ever posted and the Android 11+ system media card never appears.
         *
         * Referencing the resource from real code makes it provably reachable.
         * ./gradlew :app:assembleRelease prints a "resource ... appears to be
         * unused" warning naming this line; that warning is expected and this
         * reference is load-bearing. See res/raw/keep.xml for the rest of the
         * Dart-referenced icons.
         */
        @Suppress("unused")
        private fun keepMediaNotificationIcon(activity: MainActivity) {
            // Referencing the generated R field is what actually marks the
            // resource reachable; the lookup only makes the value observable.
            // getResourceEntryName is used instead of getDrawable because it
            // carries no API-level or deprecation caveats.
            activity.resources.getResourceEntryName(R.drawable.ic_stat_synthbox)
        }

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
