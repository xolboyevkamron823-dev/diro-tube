package com.carrozzeria.tube.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CyberAccentAmber
import com.carrozzeria.tube.ui.theme.MetalBezel
import com.carrozzeria.tube.ui.theme.OelCyan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * Pioneer Carrozzeria Signature Rotary Aluminum Dial
 * Flawless continuous pointerInput(Unit) tracking for smooth volume control
 */
@Composable
fun CarrozzeriaRotaryKnob(
    value: Float, // 0.0 to 1.0
    themeStyle: CarrozzeriaThemeStyle,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    val currentVal by rememberUpdatedState(value)
    val onValChange by rememberUpdatedState(onValueChange)

    val rotationAngle = (value.coerceIn(0f, 1f) * 270f) - 135f
    val accentColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberAccentAmber

    Box(
        modifier = modifier
            .size(76.dp)
            .pointerInput(Unit) {
                var lastAngle = 0.0
                var currentAccumulated = currentVal
                var lastStep = (currentVal * 40).toInt()
                detectDragGestures(
                    onDragStart = { offset ->
                        val center = Offset(size.width / 2f, size.height / 2f)
                        lastAngle = Math.toDegrees(atan2((offset.y - center.y).toDouble(), (offset.x - center.x).toDouble()))
                        currentAccumulated = currentVal
                        lastStep = (currentVal * 40).toInt()
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        val center = Offset(size.width / 2f, size.height / 2f)
                        val currentAngle = Math.toDegrees(atan2((change.position.y - center.y).toDouble(), (change.position.x - center.x).toDouble()))

                        var angleDiff = currentAngle - lastAngle
                        if (angleDiff > 180.0) angleDiff -= 360.0
                        if (angleDiff < -180.0) angleDiff += 360.0

                        // Both circular and vertical drags are supported smoothly
                        val circularDelta = (angleDiff / 200.0).toFloat()
                        val verticalDelta = -dragAmount.y / 150f

                        val delta = if (kotlin.math.abs(angleDiff) > 1.2) circularDelta else verticalDelta
                        currentAccumulated = (currentAccumulated + delta).coerceIn(0f, 1f)

                        val currentStep = (currentAccumulated * 40).toInt()
                        if (currentStep != lastStep) {
                            PioneerSoundEffects.playKnobTick()
                            lastStep = currentStep
                        }

                        lastAngle = currentAngle
                        onValChange(currentAccumulated)
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(70.dp)) {
            val center = Offset(size.width / 2f, size.height / 2f)
            val radius = size.minDimension / 2f

            // 1. Outer knurled metallic rim
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(Color(0xFF37474F), MetalBezel, Color(0xFF10151C)),
                    center = center,
                    radius = radius
                ),
                radius = radius,
                center = center
            )

            // Outer dial ring
            drawCircle(
                color = Color(0xFF607D8B).copy(alpha = 0.5f),
                radius = radius - 2f,
                center = center,
                style = Stroke(width = 2f)
            )

            // 2. Ticks around the dial
            val tickCount = 20
            for (i in 0 until tickCount) {
                val tickAngle = Math.toRadians((-135.0 + i * (270.0 / (tickCount - 1))))
                val startX = center.x + (radius - 8f) * cos(tickAngle).toFloat()
                val startY = center.y + (radius - 8f) * sin(tickAngle).toFloat()
                val endX = center.x + (radius - 3f) * cos(tickAngle).toFloat()
                val endY = center.y + (radius - 3f) * sin(tickAngle).toFloat()

                val tickActive = (-135.0 + i * (270.0 / (tickCount - 1))) <= rotationAngle
                drawLine(
                    color = if (tickActive) accentColor else Color(0xFF263238),
                    start = Offset(startX, startY),
                    end = Offset(endX, endY),
                    strokeWidth = 2f
                )
            }

            // 3. Inner brushed dial face
            drawCircle(
                brush = Brush.linearGradient(
                    colors = listOf(Color(0xFF263238), Color(0xFF1C2229), Color(0xFF0F141A))
                ),
                radius = radius - 12f,
                center = center
            )

            // 4. Indicator pointer notch
            val pointerRad = Math.toRadians((rotationAngle - 90.0))
            val dotDist = radius - 18f
            val dotX = center.x + dotDist * cos(pointerRad).toFloat()
            val dotY = center.y + dotDist * sin(pointerRad).toFloat()

            drawCircle(
                color = accentColor,
                radius = 3.5f,
                center = Offset(dotX, dotY)
            )
        }
    }
}
