package com.carrozzeria.tube.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = OelCyan,
    secondary = OelAmber,
    tertiary = CyberNeonBlue,
    background = PitchBlack,
    surface = DarkFrame,
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onBackground = OelWhite,
    onSurface = OelWhite
)

@Composable
fun CarrozzeriaTubeTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
