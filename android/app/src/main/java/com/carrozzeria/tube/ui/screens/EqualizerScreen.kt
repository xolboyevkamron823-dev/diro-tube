package com.carrozzeria.tube.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import com.carrozzeria.tube.core.audiofx.CarrozzeriaDspManager
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import com.carrozzeria.tube.core.model.EqBand
import com.carrozzeria.tube.core.model.EqPreset
import com.carrozzeria.tube.core.model.SoundFieldMode
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CyberAccentAmber
import com.carrozzeria.tube.ui.theme.CyberBg
import com.carrozzeria.tube.ui.theme.CyberNeonBlue
import com.carrozzeria.tube.ui.theme.DarkFrame
import com.carrozzeria.tube.ui.theme.MetalBezel
import com.carrozzeria.tube.ui.theme.OelAmber
import com.carrozzeria.tube.ui.theme.OelBg
import com.carrozzeria.tube.ui.theme.OelCyan
import com.carrozzeria.tube.ui.theme.OelCyanBright
import com.carrozzeria.tube.ui.theme.OelWhite
import com.carrozzeria.tube.ui.theme.PitchBlack

@Composable
fun EqualizerScreen(
    dspManager: CarrozzeriaDspManager,
    themeStyle: CarrozzeriaThemeStyle,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    LaunchedEffect(Unit) {
        dspManager.setContext(context)
    }

    val dspSettings by dspManager.settings.collectAsState()
    val accentColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberNeonBlue
    val screenBg = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) PitchBlack else CyberBg

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(screenBg)
            .padding(12.dp)
            .verticalScroll(rememberScrollState())
    ) {
        // Top Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(DarkFrame, RoundedCornerShape(8.dp))
                .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = {
                PioneerSoundEffects.playClick()
                onBack()
            }) {
                Icon(
                    imageVector = Icons.Default.ArrowBack,
                    contentDescription = "Back",
                    tint = OelWhite
                )
            }
            Spacer(modifier = Modifier.width(6.dp))
            Icon(
                imageVector = Icons.Default.GraphicEq,
                contentDescription = null,
                tint = accentColor,
                modifier = Modifier.size(22.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column {
                Text(
                    text = "CARROZZERIA AUDIO DSP",
                    color = OelWhite,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    text = "PROFESSIONAL SOUND TUNING & EQUALIZER",
                    color = accentColor,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // 0. Carrozzeria SFC / LIVE STAGE REJIMLARI (Real-time Live DSP)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "// SOUND FIELD (LIVE / JONLI REJIMLAR)",
                color = OelAmber,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "REAL-TIME DSP",
                color = Color(0xFF00E676),
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold
            )
        }
        Spacer(modifier = Modifier.height(6.dp))

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            items(SoundFieldMode.values()) { mode ->
                val isSelected = dspSettings.soundField == mode
                Box(
                    modifier = Modifier
                        .background(
                            if (isSelected) Color(0xFF00E676) else DarkFrame,
                            RoundedCornerShape(6.dp)
                        )
                        .border(
                            1.dp,
                            if (isSelected) OelWhite else MetalBezel,
                            RoundedCornerShape(6.dp)
                        )
                        .clickable {
                            PioneerSoundEffects.playClick()
                            dspManager.setSoundField(mode)
                        }
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                ) {
                    Text(
                        text = if (mode == SoundFieldMode.LIVE_STAGE) "🔴 LIVE STAGE" else mode.displayName,
                        color = if (isSelected) Color.Black else OelWhite,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // 1. Equalizer Presets
        Text(
            text = "// EQ PRESET SELECTOR",
            color = OelAmber,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(6.dp))

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            items(EqPreset.values()) { preset ->
                val isSelected = dspSettings.currentPreset == preset
                Box(
                    modifier = Modifier
                        .background(
                            if (isSelected) accentColor else DarkFrame,
                            RoundedCornerShape(6.dp)
                        )
                        .border(
                            1.dp,
                            if (isSelected) OelWhite else MetalBezel,
                            RoundedCornerShape(6.dp)
                        )
                        .clickable {
                            PioneerSoundEffects.playClick()
                            dspManager.applyPreset(preset)
                        }
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                ) {
                    Text(
                        text = preset.displayName,
                        color = if (isSelected) Color.Black else OelWhite,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 2. Graphic Equalizer Sliders
        Text(
            text = "// GRAPHIC EQUALIZER BANDS (±12dB)",
            color = OelAmber,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(DarkFrame, RoundedCornerShape(8.dp))
                .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
                .padding(12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                dspSettings.bands.forEach { band ->
                    BandSlider(
                        band = band,
                        accentColor = accentColor,
                        onGainChanged = { gainMilliBels ->
                            dspManager.setBandGain(band.index, gainMilliBels)
                        }
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Custom Save Buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .background(Color(0xFF00382B), RoundedCornerShape(6.dp))
                    .border(1.5.dp, Color(0xFF00E676), RoundedCornerShape(6.dp))
                    .clickable {
                        PioneerSoundEffects.playSuccessBeep()
                        dspManager.saveCustomPreset(context, EqPreset.CUSTOM_1)
                    }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "💾 SAVE TO CUSTOM 1",
                    color = Color(0xFF00E676),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace
                )
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .background(Color(0xFF002938), RoundedCornerShape(6.dp))
                    .border(1.5.dp, accentColor, RoundedCornerShape(6.dp))
                    .clickable {
                        PioneerSoundEffects.playSuccessBeep()
                        dspManager.saveCustomPreset(context, EqPreset.CUSTOM_2)
                    }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "💾 SAVE TO CUSTOM 2",
                    color = accentColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // 3. Carrozzeria Special Sound Modules
        Text(
            text = "// PIONEER ADVANCED SOUND MODULES",
            color = OelAmber,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))

        // A.S.R (Advanced Sound Retriever)
        DspFeatureCard(
            title = "ADVANCED SOUND RETRIEVER (A.S.R)",
            subtitle = "Restores high-frequency harmonics lost in YouTube compression",
            enabled = dspSettings.asrEnabled,
            onToggle = { dspManager.setAdvancedSoundRetriever(it, dspSettings.asrLevel) },
            accentColor = accentColor
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Loudness
        DspFeatureCard(
            title = "CARROZZERIA LOUDNESS",
            subtitle = "Compensates low and high frequencies at low volume levels",
            enabled = dspSettings.loudnessEnabled,
            onToggle = { dspManager.setLoudness(it, dspSettings.loudnessLevel) },
            accentColor = accentColor
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Super Todoroki Bass / Bass Boost
        DspFeatureCard(
            title = "SUPER TODOROKI BASS / SUBWOOFER",
            subtitle = "Pioneer club subwoofer punch and low-frequency resonance",
            enabled = dspSettings.bassBoostEnabled,
            onToggle = { dspManager.setBassBoost(it, dspSettings.bassBoostStrength) },
            accentColor = accentColor
        )

        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
fun BandSlider(
    band: EqBand,
    accentColor: Color,
    onGainChanged: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = band.label,
            color = OelWhite,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(44.dp)
        )

        val sliderProgress = (band.gainMillibels - band.minGainMillibels).toFloat() /
                (band.maxGainMillibels - band.minGainMillibels).toFloat()

        Slider(
            value = sliderProgress,
            onValueChange = { ratio ->
                val targetGain = (band.minGainMillibels + ratio * (band.maxGainMillibels - band.minGainMillibels)).toInt()
                onGainChanged(targetGain)
            },
            colors = SliderDefaults.colors(
                thumbColor = accentColor,
                activeTrackColor = accentColor,
                inactiveTrackColor = Color(0xFF1E2836)
            ),
            modifier = Modifier.weight(1f)
        )

        Spacer(modifier = Modifier.width(8.dp))

        Text(
            text = "${if (band.gainDb >= 0) "+" else ""}${String.format("%.1f", band.gainDb)}dB",
            color = if (band.gainDb > 0) OelAmber else OelCyanBright,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.width(52.dp)
        )
    }
}

@Composable
fun DspFeatureCard(
    title: String,
    subtitle: String,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit,
    accentColor: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkFrame, RoundedCornerShape(8.dp))
            .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
            .padding(12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = OelWhite,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = subtitle,
                color = Color.LightGray,
                fontSize = 10.sp,
                fontFamily = FontFamily.Monospace
            )
        }

        Switch(
            checked = enabled,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedThumbColor = accentColor,
                checkedTrackColor = accentColor.copy(alpha = 0.4f),
                uncheckedThumbColor = Color.Gray,
                uncheckedTrackColor = MetalBezel
            )
        )
    }
}
