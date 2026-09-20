package com.carrozzeria.tube.ui.components

import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.view.Surface
import android.view.TextureView
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CyberAccentAmber
import com.carrozzeria.tube.ui.theme.CyberBg
import com.carrozzeria.tube.ui.theme.CyberNeonBlue
import com.carrozzeria.tube.ui.theme.CyberRed
import com.carrozzeria.tube.ui.theme.LedInactive
import com.carrozzeria.tube.ui.theme.OelBg
import com.carrozzeria.tube.ui.theme.OelCyan
import com.carrozzeria.tube.ui.theme.OelCyanBright
import com.carrozzeria.tube.ui.theme.OelGridLine
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

enum class OelMode {
    VIDEO,   // Authentic 1.mp4 Pioneer dolphin video motion
    DUAL,    // Video in background + VFD Spectrum overlay
    SPECTRUM // Classic OEL Dot-Matrix Canvas dolphins + Spectrum
}

@Composable
fun PioneerDolphinVideoView(
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val rawResId = remember(context) {
        val directId = com.carrozzeria.tube.R.raw.pioneer_dolphins
        if (directId != 0) directId else context.resources.getIdentifier("pioneer_dolphins", "raw", context.packageName)
    }

    if (rawResId != 0) {
        AndroidView(
            factory = { ctx ->
                TextureView(ctx).apply {
                    surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                        private var mediaPlayer: MediaPlayer? = null

                        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                            try {
                                val uri = Uri.parse("android.resource://${ctx.packageName}/$rawResId")
                                mediaPlayer = MediaPlayer().apply {
                                    setSurface(Surface(surface))
                                    setDataSource(ctx, uri)
                                    isLooping = true
                                    setVolume(0f, 0f) // Keep muted - no sound conflict
                                    setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
                                    prepareAsync()
                                    setOnPreparedListener { mp ->
                                        mp.start()
                                    }
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("PioneerDolphinVideo", "Error initializing MediaPlayer", e)
                            }
                        }

                        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}

                        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                            try {
                                mediaPlayer?.stop()
                                mediaPlayer?.release()
                                mediaPlayer = null
                            } catch (e: Exception) {}
                            return true
                        }

                        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
                    }
                }
            },
            modifier = modifier
        )
    }
}

/**
 * Pioneer Carrozzeria Signature Dual-Engine OEL / VFD Spectrum Visualizer
 * Features:
 * 1. Authentic 1.mp4 Pioneer Jumping Dolphins Video from PC (Downloads/1.mp4)
 * 2. 16-Band Segmented Dot-Matrix / Fluorescent Spectrum Equalizer
 * 3. Upper Lagoon & Lower VFD Dual-Zone Architecture
 */
@Composable
fun VfdSpectrumVisualizer(
    spectrumData: FloatArray,
    themeStyle: CarrozzeriaThemeStyle,
    isPlaying: Boolean,
    modifier: Modifier = Modifier
) {
    var oelMode by remember { mutableStateOf(OelMode.VIDEO) }

    val infiniteTransition = rememberInfiniteTransition(label = "OelDolphinLoop")
    val dolphinProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 4200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "DolphinProgress"
    )

    val bgColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelBg else CyberBg
    val borderColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan.copy(alpha = 0.55f) else CyberNeonBlue.copy(alpha = 0.55f)
    val dolphinColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyanBright else CyberNeonBlue
    val dolphinAccent = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberAccentAmber

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(145.dp)
            .background(bgColor, RoundedCornerShape(8.dp))
            .border(1.5.dp, borderColor, RoundedCornerShape(8.dp))
            .clip(RoundedCornerShape(8.dp))
    ) {
        // 1. Authentic Pioneer Dolphin Video Motion (1.mp4)
        if (oelMode == OelMode.VIDEO || oelMode == OelMode.DUAL) {
            PioneerDolphinVideoView(modifier = Modifier.fillMaxSize())
        }

        if (oelMode != OelMode.VIDEO) {
            Canvas(modifier = Modifier.fillMaxSize()) {
            val width = size.width
            val height = size.height

            // 1. Subtle OEL Dot Matrix / CRT Scanlines Background
            val scanlineCount = 14
            val scanlineGap = height / scanlineCount
            for (i in 0..scanlineCount) {
                val y = i * scanlineGap
                drawLine(
                    color = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelGridLine else Color(0x180077FF),
                    start = Offset(0f, y),
                    end = Offset(width, y),
                    strokeWidth = 1f
                )
            }

            // =========================================================================
            // ZONE 1: UPPER OEL OCEAN LAGOON (DOLPHIN PARADISE)
            // =========================================================================
            if (oelMode == OelMode.SPECTRUM) {
                val waterY = height * 0.46f

            // Dot-matrix animated double ocean wave ripple
            val waveSteps = 40
            val stepWidth = width / waveSteps
            for (w in 0..waveSteps) {
                val wx = w * stepWidth
                val waveOffset1 = sin((w * 0.55f) + (dolphinProgress * 6f * PI.toFloat())) * 3.2f
                val waveOffset2 = cos((w * 0.45f) + (dolphinProgress * 5f * PI.toFloat())) * 2.2f

                // Upper water ripple line
                drawCircle(
                    color = dolphinColor.copy(alpha = 0.50f),
                    radius = 1.6f,
                    center = Offset(wx, waterY + waveOffset1)
                )

                // Sub-surface ripple line
                drawCircle(
                    color = dolphinAccent.copy(alpha = 0.30f),
                    radius = 1.2f,
                    center = Offset(wx, waterY + 5.5f + waveOffset2)
                )
            }

            // Continuous leaping animation: Two dolphins (Mama + Baby)
            // Using spatial loop so dolphins seamlessly cross and reappear without dead time
            val loopDistance = width + 180f
            val mamaBaseX = ((dolphinProgress * loopDistance) % loopDistance) - 90f

            // Calculate leap trajectory for Mama Dolphin
            val leapWavelength = 160f
            val leapPhaseMama = (mamaBaseX / leapWavelength) * (2f * PI.toFloat())
            val isLeapingMama = sin(leapPhaseMama) > 0f

            val mamaY = if (isLeapingMama) {
                // In the air (jumping upwards, arcing over water)
                waterY - 4f - (sin(leapPhaseMama) * (height * 0.32f))
            } else {
                // In the water (diving, swimming under surface)
                waterY + 4f + (abs(sin(leapPhaseMama)) * 7f)
            }

            // Direction vector tangent to calculate rotation angle
            val dMamaX = 1.0f
            val dMamaY = -cos(leapPhaseMama) * 0.75f
            val mamaAngle = (atan2(dMamaY, dMamaX) * (180f / PI.toFloat())).coerceIn(-48f, 48f)

            // Trailing splash droplets
            if (isLeapingMama) {
                for (s in 1..4) {
                    val splashX = mamaBaseX - (s * 14f)
                    val splashY = waterY - (sin(leapPhaseMama) * 8f) + (s * 3f)
                    if (splashX in 0f..width && splashY in 0f..height) {
                        drawCircle(
                            color = Color.White.copy(alpha = 0.75f),
                            radius = 1.6f,
                            center = Offset(splashX, splashY)
                        )
                    }
                }
            }

            // Draw Mama Dolphin
            if (mamaBaseX in -90f..(width + 90f)) {
                drawAuthenticCarrozzeriaDolphin(
                    drawScope = this,
                    centerX = mamaBaseX,
                    centerY = mamaY,
                    scale = 0.44f,
                    rotationDeg = mamaAngle,
                    fillColor = dolphinColor,
                    strokeColor = Color.White
                )
            }

            // Baby Dolphin (follows Mama closely, leaps synchronously with phase offset)
            val babyBaseX = mamaBaseX - 68f
            val leapPhaseBaby = ((babyBaseX + 20f) / leapWavelength) * (2f * PI.toFloat())
            val isLeapingBaby = sin(leapPhaseBaby) > 0f

            val babyY = if (isLeapingBaby) {
                waterY - 2f - (sin(leapPhaseBaby) * (height * 0.25f))
            } else {
                waterY + 3f + (abs(sin(leapPhaseBaby)) * 6f)
            }

            val dBabyY = -cos(leapPhaseBaby) * 0.65f
            val babyAngle = (atan2(dBabyY, dMamaX) * (180f / PI.toFloat())).coerceIn(-45f, 45f)

            if (babyBaseX in -70f..(width + 70f)) {
                drawAuthenticCarrozzeriaDolphin(
                    drawScope = this,
                    centerX = babyBaseX,
                    centerY = babyY,
                    scale = 0.28f,
                    rotationDeg = babyAngle,
                    fillColor = dolphinAccent,
                    strokeColor = dolphinColor
                )
            }

            // Staggered Sister Dolphin (guarantees a dolphin is ALWAYS visible even if Mama is wrapping)
            val sisterBaseX = ((mamaBaseX + (loopDistance * 0.55f)) % loopDistance) - 90f
            val leapPhaseSister = (sisterBaseX / leapWavelength) * (2f * PI.toFloat())
            val isLeapingSister = sin(leapPhaseSister) > 0f

            val sisterY = if (isLeapingSister) {
                waterY - 4f - (sin(leapPhaseSister) * (height * 0.30f))
            } else {
                waterY + 4f + (abs(sin(leapPhaseSister)) * 6f)
            }
            val dSisterY = -cos(leapPhaseSister) * 0.70f
            val sisterAngle = (atan2(dSisterY, dMamaX) * (180f / PI.toFloat())).coerceIn(-48f, 48f)

            if (sisterBaseX in -80f..(width + 80f)) {
                drawAuthenticCarrozzeriaDolphin(
                    drawScope = this,
                    centerX = sisterBaseX,
                    centerY = sisterY,
                    scale = 0.38f,
                    rotationDeg = sisterAngle,
                    fillColor = dolphinColor.copy(alpha = 0.9f),
                    strokeColor = Color.White
                )
            }
            }

            // =========================================================================
            // ZONE 2: LOWER 16-BAND PIONEER VFD / SPECTRUM EQUALIZER BARS
            // =========================================================================
            val vfdTop = height * 0.53f
            val vfdBottom = height - 6f
            val vfdHeight = vfdBottom - vfdTop

            val barCount = 16
            val totalGap = (barCount + 1) * 4.5f
            val barWidth = (width - totalGap) / barCount
            val segmentHeight = 5.0f
            val segmentGap = 2.0f
            val maxSegments = (vfdHeight / (segmentHeight + segmentGap)).toInt().coerceAtLeast(4)

            for (b in 0 until barCount) {
                val rawEnergy = if (b < spectrumData.size) spectrumData[b] else 0.15f
                val activeSegments = (rawEnergy * maxSegments).toInt().coerceIn(1, maxSegments)
                val x = 4.5f + b * (barWidth + 4.5f)

                for (s in 0 until maxSegments) {
                    val y = vfdBottom - (s + 1) * (segmentHeight + segmentGap)
                    val isActive = s <= activeSegments

                    val segColor = when {
                        !isActive -> LedInactive
                        s >= maxSegments - 2 -> CyberRed // Top Red Overdrive
                        s >= maxSegments - 4 -> CyberAccentAmber // Amber Warning
                        else -> if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberNeonBlue
                    }

                    drawRoundRect(
                        color = segColor,
                        topLeft = Offset(x, y),
                        size = Size(barWidth, segmentHeight),
                        cornerRadius = CornerRadius(1.5f, 1.5f)
                    )
                }

                // Peak hold indicator dot at top of active segments
                val peakY = vfdBottom - (activeSegments + 1) * (segmentHeight + segmentGap) - 1.5f
                if (peakY >= vfdTop) {
                    drawRoundRect(
                        color = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyanBright else CyberAccentAmber,
                        topLeft = Offset(x, peakY),
                        size = Size(barWidth, 2f),
                        cornerRadius = CornerRadius(1f, 1f)
                    )
                }
            }
        }
        }

        // Top Overlay Bar: Status & Mode switcher
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                modifier = Modifier
                    .background(Color(0xD00A121A), RoundedCornerShape(4.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "PIONEER OEL // CARROZZERIA",
                    color = dolphinColor,
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                modifier = Modifier
                    .background(Color(0xD00A121A), RoundedCornerShape(4.dp))
                    .border(1.dp, dolphinAccent.copy(alpha = 0.7f), RoundedCornerShape(4.dp))
                    .clickable {
                        PioneerSoundEffects.playClick()
                        oelMode = when (oelMode) {
                            OelMode.VIDEO -> OelMode.DUAL
                            OelMode.DUAL -> OelMode.SPECTRUM
                            OelMode.SPECTRUM -> OelMode.VIDEO
                        }
                    }
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = when (oelMode) {
                        OelMode.VIDEO -> "🐬 DELFIN (1.MP4)"
                        OelMode.DUAL -> "🐬 DUAL (VIDEO+EQ)"
                        OelMode.SPECTRUM -> "📊 VFD SPEKTR"
                    },
                    color = dolphinAccent,
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

/**
 * Renders an anatomically accurate, forward-facing (+X) Pioneer Carrozzeria Dolphin.
 * - Center of rotation is at (0, 0)
 * - Snout / head points forward (+X direction)
 * - Tail flukes are at the back (-X direction)
 * - Dorsal fin curves backwards-upwards
 * - Pectoral flipper fin curves downwards-backwards
 * - Fluorescent glowing body fill + crisp neon outer contour + bright white eye
 */
private fun drawAuthenticCarrozzeriaDolphin(
    drawScope: DrawScope,
    centerX: Float,
    centerY: Float,
    scale: Float,
    rotationDeg: Float,
    fillColor: Color,
    strokeColor: Color
) {
    drawScope.translate(centerX, centerY) {
        drawScope.rotate(rotationDeg, Offset.Zero) {
            val path = Path().apply {
                // 1. Snout / beak tip (leads in +X direction)
                moveTo(60f * scale, -2f * scale)

                // 2. Forehead melon curve
                cubicTo(50f * scale, -10f * scale, 35f * scale, -18f * scale, 15f * scale, -20f * scale)

                // 3. Arched back to dorsal fin base
                cubicTo(0f * scale, -21f * scale, -10f * scale, -21f * scale, -18f * scale, -20f * scale)

                // 4. Dorsal fin (pointing backwards and up)
                cubicTo(-24f * scale, -38f * scale, -32f * scale, -44f * scale, -40f * scale, -42f * scale)
                cubicTo(-36f * scale, -30f * scale, -32f * scale, -22f * scale, -38f * scale, -18f * scale)

                // 5. Back down to caudal peduncle (tail base)
                cubicTo(-50f * scale, -14f * scale, -62f * scale, -8f * scale, -72f * scale, -3f * scale)

                // 6. Upper tail fluke lobe
                cubicTo(-82f * scale, -12f * scale, -92f * scale, -18f * scale, -100f * scale, -22f * scale)

                // 7. Fluke center notch
                cubicTo(-94f * scale, -10f * scale, -90f * scale, -4f * scale, -88f * scale, -1f * scale)

                // 8. Lower tail fluke lobe
                cubicTo(-92f * scale, +6f * scale, -96f * scale, +14f * scale, -100f * scale, +20f * scale)

                // 9. Tail underbelly curve back to peduncle
                cubicTo(-90f * scale, +12f * scale, -80f * scale, +6f * scale, -72f * scale, +2f * scale)

                // 10. Underbelly curve forward to chest
                cubicTo(-55f * scale, +8f * scale, -30f * scale, +14f * scale, -5f * scale, +16f * scale)

                // 11. Pectoral flipper fin (pointing down and back)
                cubicTo(+2f * scale, +26f * scale, +8f * scale, +38f * scale, +18f * scale, +34f * scale)
                cubicTo(+16f * scale, +26f * scale, +14f * scale, +18f * scale, +18f * scale, +14f * scale)

                // 12. Throat and chin back to snout
                cubicTo(+32f * scale, +12f * scale, +48f * scale, +6f * scale, +60f * scale, -2f * scale)
                close()
            }

            // Fluorescent glowing body fill
            drawPath(
                path = path,
                color = fillColor.copy(alpha = 0.85f)
            )

            // Crisp neon stroke outline
            drawPath(
                path = path,
                color = strokeColor,
                style = Stroke(width = 2.2f)
            )

            // Bright sparkling eye dot
            drawCircle(
                color = Color.White,
                radius = 2.6f * scale + 0.8f,
                center = Offset(42f * scale, -6f * scale)
            )

            // Pectoral fin detail crease line
            drawLine(
                color = strokeColor.copy(alpha = 0.6f),
                start = Offset(5f * scale, +16f * scale),
                end = Offset(12f * scale, +26f * scale),
                strokeWidth = 1.2f
            )
        }
    }
}
