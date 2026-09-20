package com.carrozzeria.tube.ui.theme

import androidx.compose.ui.graphics.Color

// Carrozzeria Common
val PitchBlack = Color(0xFF07090C)
val MetalBezel = Color(0xFF1B2028)
val DarkFrame = Color(0xFF10141C)
val LedInactive = Color(0xFF15222E)

// Theme 1: Classic OEL Retro (Pioneer DEH-P88RS / Carrozzeria MEH-P9000)
val OelCyan = Color(0xFF00E5FF)
val OelCyanBright = Color(0xFF80F0FF)
val OelWhite = Color(0xFFE6FFFF)
val OelBg = Color(0xFF041017)
val OelGridLine = Color(0x3300E5FF)
val OelAmber = Color(0xFFFFB300)

// Theme 2: Cyber Navi Modern (Futuristic Head Unit)
val CyberBg = Color(0xFF0C0E14)
val CyberPanel = Color(0xFF161922)
val CyberNeonBlue = Color(0xFF0077FF)
val CyberAccentAmber = Color(0xFFFF9100)
val CyberRed = Color(0xFFFF2A55)
val CyberGreen = Color(0xFF00E676)
val CyberTextMuted = Color(0xFF78889B)

enum class CarrozzeriaThemeStyle(val displayName: String, val description: String) {
    CLASSIC_OEL("CLASSIC OEL RETRO", "Afsonaviy 2000-yillar pikselli moviy OEL displeyi va animatsiyalar"),
    CYBER_NAVI("CYBER NAVI MODERN", "Zamonaviy sensorli avtomobil tizimi, kiber panellar va HUD ko'rinishi")
}
