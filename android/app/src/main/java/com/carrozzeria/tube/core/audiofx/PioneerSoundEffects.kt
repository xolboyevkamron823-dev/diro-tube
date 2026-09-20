package com.carrozzeria.tube.core.audiofx

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Pioneer Carrozzeria Signature Tactile Sound & Haptic Feedback Engine
 * Plays crisp, authentic mechanical beeps and clicks on every button interaction.
 */
object PioneerSoundEffects {

    private const val TAG = "PioneerSoundEffects"

    private var toneGenerator: ToneGenerator? = null
    private var vibrator: Vibrator? = null
    var soundEnabled: Boolean = true
    var hapticsEnabled: Boolean = true

    fun init(context: Context) {
        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 70)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize ToneGenerator", e)
        }

        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Vibrator", e)
        }
    }

    /**
     * Standard Pioneer Carrozzeria tactile button click (Soft high-tech click)
     */
    fun playClick() {
        if (!soundEnabled) return
        try {
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 30) // 30ms snappy beep
        } catch (e: Exception) { }

        performLightHaptic()
    }

    /**
     * Rotary Knob tick sound (Ultra-snappy micro click)
     */
    fun playKnobTick() {
        if (!soundEnabled) return
        try {
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_ACK, 20)
        } catch (e: Exception) { }

        performTickHaptic()
    }

    /**
     * Confirmation chirp (e.g. Preset saved, theme switched)
     */
    fun playSuccessBeep() {
        if (!soundEnabled) return
        try {
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP2, 60)
        } catch (e: Exception) { }

        performLightHaptic()
    }

    private fun performLightHaptic() {
        if (!hapticsEnabled) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(15, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(15)
            }
        } catch (e: Exception) { }
    }

    private fun performTickHaptic() {
        if (!hapticsEnabled) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                vibrator?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(10)
            }
        } catch (e: Exception) { }
    }

    fun release() {
        try {
            toneGenerator?.release()
        } catch (e: Exception) { }
        toneGenerator = null
        vibrator = null
    }
}
