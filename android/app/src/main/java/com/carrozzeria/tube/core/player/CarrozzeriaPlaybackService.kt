package com.carrozzeria.tube.core.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import androidx.annotation.OptIn
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.carrozzeria.tube.MainActivity
import com.carrozzeria.tube.R
import com.carrozzeria.tube.core.audiofx.CarrozzeriaDspManager

/**
 * AndroidX Media3 Background Playback Service.
 * Guarantees audio keeps playing when:
 * 1. Screen is turned off / phone is locked.
 * 2. User switches to other apps (Telegram, Instagram, Games, etc.).
 */
class CarrozzeriaPlaybackService : MediaSessionService() {

    companion object {
        const val CHANNEL_ID = "carrozzeria_playback_channel"
        const val NOTIFICATION_ID = 1010
        val dspManager = CarrozzeriaDspManager()
        var activePlayer: ExoPlayer? = null
            private set
    }

    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // Acquire WakeLock and WifiLock for non-stop background streaming
        acquireLocks()

        // 1. Configure ExoPlayer with Car Audio Attributes
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .setUsage(C.USAGE_MEDIA)
            .build()

        val dataSourceFactory = androidx.media3.datasource.DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36")
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(20000)
            .setAllowCrossProtocolRedirects(true)
        val mediaSourceFactory = androidx.media3.exoplayer.source.DefaultMediaSourceFactory(this)
            .setDataSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setAudioAttributes(audioAttributes, true) // Auto-handle audio focus
            .setHandleAudioBecomingNoisy(true)        // Pause when headphones unplugged
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build().apply {
                repeatMode = Player.REPEAT_MODE_OFF
                addListener(object : Player.Listener {
                    override fun onAudioSessionIdChanged(audioSessionId: Int) {
                        dspManager.attachAudioSession(audioSessionId)
                        if (dspManager.reverbEffectId != 0) {
                            try {
                                setAuxEffectInfo(androidx.media3.common.AuxEffectInfo(dspManager.reverbEffectId, 1.0f))
                            } catch (e: Exception) { }
                        }
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_READY) {
                            dspManager.attachAudioSession(audioSessionId)
                            if (dspManager.reverbEffectId != 0) {
                                try {
                                    setAuxEffectInfo(androidx.media3.common.AuxEffectInfo(dspManager.reverbEffectId, 1.0f))
                                } catch (e: Exception) { }
                            }
                        }
                    }
                })
            }

        activePlayer = player

        dspManager.onAuxEffectChanged = { reverbId, sendLevel ->
            try {
                if (reverbId != 0 && sendLevel > 0f) {
                    player?.setAuxEffectInfo(androidx.media3.common.AuxEffectInfo(reverbId, sendLevel))
                } else {
                    player?.setAuxEffectInfo(androidx.media3.common.AuxEffectInfo(androidx.media3.common.AuxEffectInfo.NO_AUX_EFFECT_ID, 0f))
                }
            } catch (e: Exception) { }
        }

        // 2. Open MainActivity when notification is tapped
        val sessionActivityPendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // 3. Create MediaSession
        player?.let { exo ->
            mediaSession = MediaSession.Builder(this, exo)
                .setSessionActivity(sessionActivityPendingIntent)
                .build()
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    private fun acquireLocks() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CarrozzeriaTube:PlaybackWakeLock").apply {
            this?.setReferenceCounted(false)
            this?.acquire(12 * 60 * 60 * 1000L) // 12 hours max
        }

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "CarrozzeriaTube:WifiLock").apply {
            this?.setReferenceCounted(false)
            this?.acquire()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = getString(R.string.notification_channel_name)
            val descriptionText = getString(R.string.notification_channel_desc)
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        dspManager.releaseEffects()

        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wifiLock?.let {
            if (it.isHeld) it.release()
        }

        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        activePlayer = null
    }
}
