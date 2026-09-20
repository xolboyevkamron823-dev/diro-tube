package com.carrozzeria.tube

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.carrozzeria.tube.core.player.CarrozzeriaPlaybackService
import com.carrozzeria.tube.core.player.PlayerController
import com.carrozzeria.tube.core.youtube.YouTubeRepository
import com.carrozzeria.tube.ui.screens.EqualizerScreen
import com.carrozzeria.tube.ui.screens.PlayerScreen
import com.carrozzeria.tube.ui.screens.SettingsScreen
import com.carrozzeria.tube.ui.screens.TrendingScreen
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CarrozzeriaTubeTheme
import com.carrozzeria.tube.ui.theme.PitchBlack

enum class AppScreen {
    PLAYER,
    TRENDING,
    EQUALIZER,
    SETTINGS
}

class MainActivity : ComponentActivity() {

    private lateinit var playerController: PlayerController
    private val youtubeRepository = YouTubeRepository()

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        // Notification permission granted for background playback controls
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        hideSystemBars()

        com.carrozzeria.tube.core.audiofx.PioneerSoundEffects.init(this)
        playerController = PlayerController(this, youtubeRepository)

        checkAndRequestPermissions()

        setContent {
            CarrozzeriaTubeTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = PitchBlack
                ) {
                    CarrozzeriaApp(
                        playerController = playerController,
                        repository = youtubeRepository
                    )
                }
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemBars()
        }
    }

    private fun hideSystemBars() {
        val insetsController = WindowCompat.getInsetsController(window, window.decorView)
        insetsController.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
    }

    private fun checkAndRequestPermissions() {
        // Android 13+ (API 33, 34, 35) Notification permission for background controls
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // Ignore Battery Optimization for Xiaomi, Samsung, Oppo, Vivo, OnePlus
        try {
            val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as? android.os.PowerManager
            if (powerManager != null && !powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = android.net.Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        } catch (e: Exception) {
            // Ignore if manufacturer blocks the intent
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        com.carrozzeria.tube.core.audiofx.PioneerSoundEffects.release()
        playerController.release()
    }
}

@Composable
fun CarrozzeriaApp(
    playerController: PlayerController,
    repository: YouTubeRepository
) {
    var currentScreen by remember { mutableStateOf(AppScreen.PLAYER) }
    var currentTheme by remember { mutableStateOf(CarrozzeriaThemeStyle.CLASSIC_OEL) }
    val uiState by playerController.uiState.collectAsState()

    when (currentScreen) {
        AppScreen.PLAYER -> {
            PlayerScreen(
                uiState = uiState,
                themeStyle = currentTheme,
                repository = repository,
                onTogglePlayPause = { playerController.togglePlayPause() },
                onNext = { playerController.playNext() },
                onPrevious = { playerController.playPrevious() },
                onSeek = { playerController.seekTo(it) },
                onVolumeChange = { playerController.setVolume(it) },
                onTrackSelect = { track, allTracks, index ->
                    if (allTracks.isNotEmpty()) {
                        playerController.setQueueAndPlay(allTracks, index)
                    } else {
                        playerController.playTrack(track)
                    }
                },
                onAppendQueue = { playerController.appendQueue(it) },
                onNavigateToTrending = { currentScreen = AppScreen.TRENDING },
                onNavigateToEqualizer = { currentScreen = AppScreen.EQUALIZER },
                onNavigateToSettings = { currentScreen = AppScreen.SETTINGS },
                onToggleTheme = {
                    currentTheme = if (currentTheme == CarrozzeriaThemeStyle.CLASSIC_OEL)
                        CarrozzeriaThemeStyle.CYBER_NAVI else CarrozzeriaThemeStyle.CLASSIC_OEL
                },
                onToggleAutoplay = { playerController.toggleAutoplay() }
            )
        }

        AppScreen.TRENDING -> {
            TrendingScreen(
                repository = repository,
                themeStyle = currentTheme,
                onTrackSelect = { track ->
                    playerController.playTrack(track)
                    currentScreen = AppScreen.PLAYER
                },
                onBack = { currentScreen = AppScreen.PLAYER }
            )
        }

        AppScreen.EQUALIZER -> {
            EqualizerScreen(
                dspManager = CarrozzeriaPlaybackService.dspManager,
                themeStyle = currentTheme,
                onBack = { currentScreen = AppScreen.PLAYER }
            )
        }

        AppScreen.SETTINGS -> {
            SettingsScreen(
                currentTheme = currentTheme,
                onThemeSelected = { newTheme -> currentTheme = newTheme },
                onBack = { currentScreen = AppScreen.PLAYER }
            )
        }
    }
}
