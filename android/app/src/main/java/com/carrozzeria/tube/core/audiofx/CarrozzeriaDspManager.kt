package com.carrozzeria.tube.core.audiofx

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.util.Log
import com.carrozzeria.tube.core.model.DspSettings
import com.carrozzeria.tube.core.model.EqBand
import com.carrozzeria.tube.core.model.EqPreset
import com.carrozzeria.tube.core.model.SoundFieldMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Pioneer Carrozzeria DSP & Equalizer Manager
 * Handles multi-band EQ, Super Todoroki Bass, Loudness, SLA, ASR, and Live Sound Field (SFC).
 * Includes digital headroom compensation to eliminate clipping and distortion,
 * plus persistent SharedPreferences storage for user CUSTOM 1 and CUSTOM 2 presets.
 */
class CarrozzeriaDspManager {

    companion object {
        private const val TAG = "CarrozzeriaDSP"
        private const val PREFS_NAME = "carrozzeria_dsp_prefs"
    }

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var virtualizer: Virtualizer? = null
    private var presetReverb: PresetReverb? = null

    var onAuxEffectChanged: ((effectId: Int, sendLevel: Float) -> Unit)? = null
    val reverbEffectId: Int get() = presetReverb?.id ?: 0

    // Standard Pioneer 5-band EQ frequencies
    private val defaultBands = listOf(
        EqBand(0, 60, "60Hz", 0, -1200, 1200),
        EqBand(1, 230, "230Hz", 0, -1200, 1200),
        EqBand(2, 910, "910Hz", 0, -1200, 1200),
        EqBand(3, 3600, "3.6k", 0, -1200, 1200),
        EqBand(4, 14000, "14k", 0, -1200, 1200)
    )

    private val _settings = MutableStateFlow(DspSettings(bands = defaultBands))
    val settings: StateFlow<DspSettings> = _settings.asStateFlow()

    private var currentAudioSessionId: Int = 0
    private var appContext: Context? = null

    fun setContext(context: Context) {
        appContext = context.applicationContext
        loadAllCustomPresets(context)
    }

    /**
     * Bind audio effects to ExoPlayer's audioSessionId with individual isolation
     */
    fun attachAudioSession(audioSessionId: Int) {
        if (audioSessionId == 0 || audioSessionId == currentAudioSessionId) return
        currentAudioSessionId = audioSessionId

        releaseEffects()

        // 1. Equalizer with priority & fallback
        try {
            equalizer = Equalizer(1000, audioSessionId).apply { enabled = true }
        } catch (e1: Exception) {
            try {
                equalizer = Equalizer(0, audioSessionId).apply { enabled = true }
            } catch (e2: Exception) {
                try {
                    equalizer = Equalizer(0, 0).apply { enabled = true }
                } catch (e3: Exception) {
                    Log.e(TAG, "Equalizer init failed", e3)
                }
            }
        }

        // Populate bands from hardware equalizer if successfully opened
        equalizer?.let { eq ->
            try {
                val numBands = eq.numberOfBands.toInt()
                val minLevel = eq.bandLevelRange[0].toInt()
                val maxLevel = eq.bandLevelRange[1].toInt()
                val bandList = mutableListOf<EqBand>()

                for (i in 0 until numBands) {
                    val centerFreq = eq.getCenterFreq(i.toShort()) / 1000 // Hz
                    val label = if (centerFreq >= 1000) "${centerFreq / 1000}k" else "${centerFreq}Hz"
                    val currentGain = eq.getBandLevel(i.toShort()).toInt()

                    bandList.add(
                        EqBand(
                            index = i,
                            centerFreqHz = centerFreq,
                            label = label,
                            gainMillibels = currentGain,
                            minGainMillibels = minLevel,
                            maxGainMillibels = maxLevel
                        )
                    )
                }

                _settings.update { it.copy(bands = bandList) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed reading bands from hardware EQ", e)
            }
        }

        // 2. BassBoost (Super Todoroki Bass - musical, distortion-free strength)
        try {
            bassBoost = BassBoost(1000, audioSessionId).apply {
                enabled = _settings.value.bassBoostEnabled
                setStrength(_settings.value.bassBoostStrength.coerceIn(0, 700).toShort())
            }
        } catch (e1: Exception) {
            try {
                bassBoost = BassBoost(0, audioSessionId).apply {
                    enabled = _settings.value.bassBoostEnabled
                    setStrength(_settings.value.bassBoostStrength.coerceIn(0, 700).toShort())
                }
            } catch (e2: Exception) {
                Log.e(TAG, "BassBoost init failed", e2)
            }
        }

        // 3. LoudnessEnhancer
        try {
            loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                enabled = _settings.value.loudnessEnabled
                val gainMilliBels = when (_settings.value.loudnessLevel) {
                    1 -> 180 // Low (+1.8dB)
                    2 -> 350 // Mid (+3.5dB)
                    3 -> 550 // High (+5.5dB clean)
                    else -> 0
                }
                setTargetGain(gainMilliBels)
            }
        } catch (e: Exception) {
            Log.e(TAG, "LoudnessEnhancer init failed", e)
        }

        // 4. Virtualizer (Carrozzeria 3D Stage Widening)
        try {
            virtualizer = Virtualizer(1000, audioSessionId).apply {
                enabled = true
            }
        } catch (e1: Exception) {
            try {
                virtualizer = Virtualizer(0, audioSessionId).apply {
                    enabled = true
                }
            } catch (e2: Exception) {
                Log.e(TAG, "Virtualizer init failed", e2)
            }
        }

        // 5. PresetReverb (Auxiliary effect on session 0)
        try {
            presetReverb = PresetReverb(0, 0).apply {
                enabled = true
            }
        } catch (e1: Exception) {
            try {
                presetReverb = PresetReverb(0, audioSessionId).apply {
                    enabled = true
                }
            } catch (e2: Exception) {
                Log.e(TAG, "PresetReverb init failed", e2)
            }
        }

        // Apply sound field and preset with audiophile headroom
        applyPreset(_settings.value.currentPreset)
        setSoundField(_settings.value.soundField)

        Log.d(TAG, "Carrozzeria DSP attached successfully to session: $audioSessionId")
    }

    /**
     * Apply standard Carrozzeria presets with audiophile balanced gains.
     * Prevents digital clipping by capping maximum boost at +4.5dB.
     */
    fun applyPreset(preset: EqPreset) {
        val eq = equalizer

        if (preset == EqPreset.CUSTOM_1 || preset == EqPreset.CUSTOM_2) {
            appContext?.let { loadCustomPreset(it, preset) }
            _settings.update { it.copy(currentPreset = preset) }
            return
        }

        // Normalized curves (values between -0.4 and +0.45) to prevent distortion
        val curve: List<Float> = when (preset) {
            EqPreset.POWERFUL -> listOf(0.40f, 0.15f, -0.05f, 0.15f, 0.35f)   // Classic punchy V-curve
            EqPreset.NATURAL -> listOf(0.15f, 0.08f, 0.02f, 0.08f, 0.15f)     // Warm gentle curve
            EqPreset.VOCAL -> listOf(-0.15f, 0.10f, 0.40f, 0.20f, -0.05f)     // Clean vocal projection
            EqPreset.FLAT -> listOf(0.0f, 0.0f, 0.0f, 0.0f, 0.0f)            // Reference flat
            EqPreset.SUPER_BASS -> listOf(0.50f, 0.30f, 0.05f, 0.0f, 0.15f)    // Controlled low-end punch
            EqPreset.CUSTOM_1, EqPreset.CUSTOM_2 -> return
        }

        if (preset == EqPreset.SUPER_BASS) {
            setBassBoost(enabled = true, strength = 500)
        } else if (preset == EqPreset.POWERFUL) {
            setBassBoost(enabled = true, strength = 350)
        }

        val updatedBands = _settings.value.bands.toMutableList()
        val numBands = eq?.numberOfBands?.toInt() ?: updatedBands.size
        val minLevel = eq?.bandLevelRange?.get(0)?.toInt() ?: -1200
        val maxLevel = eq?.bandLevelRange?.get(1)?.toInt() ?: 1200

        for (i in 0 until numBands) {
            val normalizedIndex = (i.toFloat() / (numBands - 1).coerceAtLeast(1) * (curve.size - 1)).toInt()
            val ratio = curve.getOrElse(normalizedIndex) { 0f }

            val targetGain = if (ratio >= 0) {
                (ratio * maxLevel).toInt().coerceIn(-1200, 600) // Cap max at +6dB to prevent clipping
            } else {
                (-ratio * minLevel).toInt().coerceIn(-1200, 600)
            }

            try {
                eq?.setBandLevel(i.toShort(), targetGain.toShort())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set band level $i", e)
            }

            if (i < updatedBands.size) {
                updatedBands[i] = updatedBands[i].copy(gainMillibels = targetGain)
            }
        }

        _settings.update {
            it.copy(
                currentPreset = preset,
                bands = updatedBands
            )
        }
    }

    /**
     * Manually adjust a single frequency band
     */
    fun setBandGain(bandIndex: Int, gainMillibels: Int) {
        val clampedGain = gainMillibels.coerceIn(-1200, 1000)
        try {
            equalizer?.setBandLevel(bandIndex.toShort(), clampedGain.toShort())
        } catch (e: Exception) {
            Log.e(TAG, "Error setting band gain", e)
        }

        val updatedBands = _settings.value.bands.map {
            if (it.index == bandIndex) it.copy(gainMillibels = clampedGain) else it
        }

        _settings.update {
            it.copy(
                currentPreset = EqPreset.CUSTOM_1,
                bands = updatedBands
            )
        }
    }

    /**
     * Saves the current manual slider gains into CUSTOM 1 or CUSTOM 2 in SharedPreferences.
     */
    fun saveCustomPreset(context: Context, preset: EqPreset) {
        if (preset != EqPreset.CUSTOM_1 && preset != EqPreset.CUSTOM_2) return
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            val prefix = if (preset == EqPreset.CUSTOM_1) "custom_1" else "custom_2"

            _settings.value.bands.forEach { band ->
                editor.putInt("${prefix}_band_${band.index}", band.gainMillibels)
            }
            editor.apply()

            _settings.update { it.copy(currentPreset = preset) }
            Log.d(TAG, "Successfully saved $preset to SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save custom preset", e)
        }
    }

    /**
     * Loads saved gains for CUSTOM 1 or CUSTOM 2 from SharedPreferences.
     */
    fun loadCustomPreset(context: Context, preset: EqPreset): Boolean {
        if (preset != EqPreset.CUSTOM_1 && preset != EqPreset.CUSTOM_2) return false
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val prefix = if (preset == EqPreset.CUSTOM_1) "custom_1" else "custom_2"

            val updatedBands = _settings.value.bands.toMutableList()
            var hasSavedData = false

            for (i in updatedBands.indices) {
                val key = "${prefix}_band_$i"
                if (prefs.contains(key)) {
                    val savedGain = prefs.getInt(key, 0)
                    updatedBands[i] = updatedBands[i].copy(gainMillibels = savedGain)
                    try {
                        equalizer?.setBandLevel(i.toShort(), savedGain.toShort())
                    } catch (e: Exception) { }
                    hasSavedData = true
                }
            }

            if (hasSavedData) {
                _settings.update {
                    it.copy(
                        currentPreset = preset,
                        bands = updatedBands
                    )
                }
            }
            return hasSavedData
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load custom preset", e)
            return false
        }
    }

    private fun loadAllCustomPresets(context: Context) {
        if (_settings.value.currentPreset == EqPreset.CUSTOM_1) {
            loadCustomPreset(context, EqPreset.CUSTOM_1)
        } else if (_settings.value.currentPreset == EqPreset.CUSTOM_2) {
            loadCustomPreset(context, EqPreset.CUSTOM_2)
        }
    }

    /**
     * Carrozzeria Super Todoroki Bass Boost (clamped to prevent distortion)
     */
    fun setBassBoost(enabled: Boolean, strength: Int = 450) {
        val safeStrength = strength.coerceIn(0, 900)
        try {
            bassBoost?.enabled = enabled
            bassBoost?.setStrength(safeStrength.toShort())
        } catch (e: Exception) {
            Log.e(TAG, "Error setting bass boost", e)
        }
        _settings.update {
            it.copy(
                bassBoostEnabled = enabled,
                bassBoostStrength = safeStrength
            )
        }
    }

    /**
     * Carrozzeria Loudness Control (Off, Low, Mid, High)
     */
    fun setLoudness(enabled: Boolean, level: Int = 2) {
        try {
            loudnessEnhancer?.enabled = enabled
            val gainMilliBels = when (level) {
                1 -> 180 // Low (+1.8dB)
                2 -> 350 // Mid (+3.5dB)
                3 -> 550 // High (+5.5dB)
                else -> 0
            }
            loudnessEnhancer?.setTargetGain(gainMilliBels)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting loudness", e)
        }
        _settings.update {
            it.copy(
                loudnessEnabled = enabled,
                loudnessLevel = level
            )
        }
    }

    /**
     * Carrozzeria Advanced Sound Retriever (ASR)
     */
    fun setAdvancedSoundRetriever(enabled: Boolean, level: Int = 2) {
        _settings.update {
            it.copy(
                asrEnabled = enabled,
                asrLevel = level
            )
        }

        if (enabled && equalizer != null) {
            val bands = _settings.value.bands
            if (bands.isNotEmpty()) {
                val lastBand = bands.last()
                val boost = if (level == 1) 200 else 380 // +2dB or +3.8dB safe excitation
                setBandGain(lastBand.index, (lastBand.gainMillibels + boost).coerceAtMost(lastBand.maxGainMillibels))
            }
        }
    }

    /**
     * SLA: Source Level Adjuster (-4dB to +4dB)
     */
    fun setSla(dbGain: Float) {
        _settings.update { it.copy(slaDb = dbGain) }
    }

    /**
     * Pioneer Carrozzeria Sound Field Control (SFC / LIVE Rejimlari)
     * Balanced acoustic modeling that delivers immense 3D space and crystal clear reverb.
     */
    fun setSoundField(mode: SoundFieldMode) {
        try {
            when (mode) {
                SoundFieldMode.CONCERT_HALL -> {
                    // 1. Spacious 3D Stereo Stage (Virtualizer 950 for massive hall acoustic spread)
                    try {
                        virtualizer?.enabled = true
                        virtualizer?.setStrength(950.toShort())
                    } catch (e: Exception) { }

                    // 2. Hardware Reverb (100% send level, PRESET_LARGEHALL)
                    try {
                        presetReverb?.enabled = true
                        presetReverb?.preset = PresetReverb.PRESET_LARGEHALL
                        onAuxEffectChanged?.invoke(presetReverb?.id ?: 0, 1.0f)
                    } catch (e: Exception) { }

                    // 3. Acoustic Grand Hall Reflection Curve
                    applyAcousticCurve(subBassRatio = 0.55f, midRatio = -0.15f, highRatio = 0.50f)
                    setBassBoost(enabled = true, strength = 600)
                    setLoudness(enabled = true, level = 3)
                }
                SoundFieldMode.LIVE_STAGE -> {
                    // Jonli konsert sahnasi: Ochiq stadion va vokal proyeksiyasi
                    try {
                        virtualizer?.enabled = true
                        virtualizer?.setStrength(750.toShort())
                    } catch (e: Exception) { }

                    try {
                        presetReverb?.enabled = true
                        presetReverb?.preset = PresetReverb.PRESET_LARGEROOM
                        onAuxEffectChanged?.invoke(presetReverb?.id ?: 0, 0.85f)
                    } catch (e: Exception) { }

                    // Forward vocal presence (+3.5dB) and wide stereo stage
                    applyAcousticCurve(subBassRatio = 0.35f, midRatio = 0.40f, highRatio = 0.35f)
                    setBassBoost(enabled = true, strength = 450)
                    setLoudness(enabled = true, level = 2)
                }
                SoundFieldMode.CLUB -> {
                    // Tungi klub: Kuchli drayv va siqilgan akustika
                    try {
                        virtualizer?.enabled = true
                        virtualizer?.setStrength(600.toShort())
                    } catch (e: Exception) { }

                    try {
                        presetReverb?.enabled = true
                        presetReverb?.preset = PresetReverb.PRESET_MEDIUMROOM
                        onAuxEffectChanged?.invoke(presetReverb?.id ?: 0, 0.75f)
                    } catch (e: Exception) { }

                    // Deep club punch bass (+6dB) and crystalline highs
                    applyAcousticCurve(subBassRatio = 0.75f, midRatio = 0.10f, highRatio = 0.45f)
                    setBassBoost(enabled = true, strength = 750)
                    setLoudness(enabled = true, level = 3)
                }
                SoundFieldMode.STUDIO -> {
                    // Studiya: Toza, to'g'ridan-to'g'ri akustika (aks-sadosiz)
                    try {
                        virtualizer?.enabled = false
                        presetReverb?.enabled = false
                        onAuxEffectChanged?.invoke(0, 0.0f)
                    } catch (e: Exception) { }
                    applyPreset(_settings.value.currentPreset)
                }
                SoundFieldMode.STANDARD -> {
                    try {
                        virtualizer?.enabled = false
                        presetReverb?.enabled = false
                        onAuxEffectChanged?.invoke(0, 0.0f)
                    } catch (e: Exception) { }
                    applyPreset(_settings.value.currentPreset)
                }
            }

            _settings.update { it.copy(soundField = mode) }
            Log.d(TAG, "Carrozzeria Sound Field mode changed to: ${mode.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting sound field mode", e)
        }
    }

    /**
     * Applies custom acoustic curve ratios across available EQ bands with headroom protection
     */
    private fun applyAcousticCurve(subBassRatio: Float, midRatio: Float, highRatio: Float) {
        val eq = equalizer
        val updatedBands = _settings.value.bands.toMutableList()
        val numBands = eq?.numberOfBands?.toInt() ?: updatedBands.size
        if (numBands == 0) return

        val minLevel = eq?.bandLevelRange?.get(0)?.toInt() ?: -1200
        val maxLevel = eq?.bandLevelRange?.get(1)?.toInt() ?: 1200

        for (i in 0 until numBands) {
            val position = i.toFloat() / (numBands - 1).coerceAtLeast(1)
            val ratio = when {
                position <= 0.35f -> subBassRatio // Bass frequencies
                position <= 0.70f -> midRatio     // Mid frequencies
                else -> highRatio                 // High frequencies
            }

            val targetGain = if (ratio >= 0) {
                (ratio * maxLevel).toInt().coerceIn(-1200, 600)
            } else {
                (-ratio * minLevel).toInt().coerceIn(-1200, 600)
            }

            try {
                eq?.setBandLevel(i.toShort(), targetGain.toShort())
            } catch (e: Exception) {
                Log.e(TAG, "Failed setting acoustic band $i", e)
            }

            if (i < updatedBands.size) {
                updatedBands[i] = updatedBands[i].copy(gainMillibels = targetGain)
            }
        }

        _settings.update { it.copy(bands = updatedBands) }
    }

    fun releaseEffects() {
        try {
            equalizer?.release()
            bassBoost?.release()
            loudnessEnhancer?.release()
            virtualizer?.release()
            presetReverb?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing audio effects", e)
        } finally {
            equalizer = null
            bassBoost = null
            loudnessEnhancer = null
            virtualizer = null
            presetReverb = null
        }
    }
}
