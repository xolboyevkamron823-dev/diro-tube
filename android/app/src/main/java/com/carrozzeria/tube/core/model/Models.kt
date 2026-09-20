package com.carrozzeria.tube.core.model

data class Track(
    val id: String,
    val title: String,
    val artist: String,
    val durationSec: Long = 0,
    val thumbnailUrl: String = "",
    val audioStreamUrl: String = "",
    val viewCount: String = "",
    val isTrending: Boolean = false
) {
    val formattedDuration: String
        get() {
            val minutes = durationSec / 60
            val seconds = durationSec % 60
            return String.format("%02d:%02d", minutes, seconds)
        }
}

enum class EqPreset(val displayName: String) {
    POWERFUL("POWERFUL"),
    NATURAL("NATURAL"),
    VOCAL("VOCAL"),
    FLAT("FLAT"),
    SUPER_BASS("SUPER BASS"),
    CUSTOM_1("CUSTOM 1"),
    CUSTOM_2("CUSTOM 2")
}

data class EqBand(
    val index: Int,
    val centerFreqHz: Int,
    val label: String,
    var gainMillibels: Int = 0,
    val minGainMillibels: Int = -1200,
    val maxGainMillibels: Int = 1200
) {
    val gainDb: Float
        get() = gainMillibels / 100f
}

enum class SoundFieldMode(val displayName: String) {
    STANDARD("STANDARD"),
    LIVE_STAGE("LIVE STAGE"),
    CLUB("CLUB SOUND"),
    CONCERT_HALL("HALL"),
    STUDIO("STUDIO")
}

data class DspSettings(
    val currentPreset: EqPreset = EqPreset.POWERFUL,
    val bands: List<EqBand> = emptyList(),
    val soundField: SoundFieldMode = SoundFieldMode.LIVE_STAGE, // Pioneer Carrozzeria Live stage
    val asrEnabled: Boolean = true, // Carrozzeria Advanced Sound Retriever
    val asrLevel: Int = 2, // 1 (Soft), 2 (Standard)
    val loudnessEnabled: Boolean = true,
    val loudnessLevel: Int = 2, // 1 (Low), 2 (Mid), 3 (High)
    val bassBoostEnabled: Boolean = true,
    val bassBoostStrength: Int = 600, // 0 to 1000
    val slaDb: Float = 0f // Source Level Adjuster (-4dB to +4dB)
)

data class PlayerUiState(
    val currentTrack: Track? = null,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val isBuffering: Boolean = false,
    val volume: Float = 0.8f,
    val visualizerData: FloatArray = FloatArray(16) { 0.1f },
    val sourceName: String = "TUBE",
    val dspSettings: DspSettings = DspSettings(),
    val autoplayEnabled: Boolean = true
) {
    val progress: Float
        get() = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
}
