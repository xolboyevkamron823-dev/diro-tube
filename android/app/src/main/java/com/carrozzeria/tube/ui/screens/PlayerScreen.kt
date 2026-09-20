package com.carrozzeria.tube.ui.screens

import android.content.res.Configuration
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.carrozzeria.tube.core.model.DspSettings
import com.carrozzeria.tube.core.model.PlayerUiState
import com.carrozzeria.tube.core.model.Track
import com.carrozzeria.tube.core.youtube.YouTubeRepository
import com.carrozzeria.tube.ui.components.CarrozzeriaRotaryKnob
import com.carrozzeria.tube.ui.components.MiniVideoBezel
import com.carrozzeria.tube.ui.components.VfdSpectrumVisualizer
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
import kotlinx.coroutines.launch

@Composable
fun PlayerScreen(
    uiState: PlayerUiState,
    themeStyle: CarrozzeriaThemeStyle,
    onTogglePlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Long) -> Unit,
    onVolumeChange: (Float) -> Unit,
    onNavigateToTrending: () -> Unit,
    onNavigateToEqualizer: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onToggleTheme: () -> Unit,
    onToggleAutoplay: () -> Unit = {},
    repository: YouTubeRepository? = null,
    onTrackSelect: (Track, List<Track>, Int) -> Unit = { _, _, _ -> },
    onAppendQueue: (List<Track>) -> Unit = {},
    modifier: Modifier = Modifier
) {
    var showMiniVideo by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    var tracks by remember { mutableStateOf<List<Track>>(emptyList()) }
    var isFeedLoading by remember { mutableStateOf(false) }
    var isMoreLoading by remember { mutableStateOf(false) }
    var currentPage by remember { mutableStateOf(1) }
    var searchQuery by remember { mutableStateOf("") }
    var selectedCategory by remember { mutableStateOf("Hammasi") }

    val portraitScrollState = rememberScrollState()

    val categories = listOf(
        "Hammasi",
        "O'zbekcha Estrada",
        "Musiqa",
        "Trending",
        "Premyera",
        "Bass & Remix",
        "Jonli ijro",
        "Xitlar 2024"
    )

    LaunchedEffect(repository) {
        if (repository != null) {
            isFeedLoading = true
            try {
                val fetched = repository.getTrendingTracks()
                tracks = fetched
                onAppendQueue(fetched)
            } catch (e: Exception) {
                // ignore
            } finally {
                isFeedLoading = false
            }
        }
    }

    // Infinite scroll listener: auto-loads next page when user scrolls near bottom
    LaunchedEffect(portraitScrollState.value, portraitScrollState.maxValue) {
        if (portraitScrollState.maxValue > 0 && portraitScrollState.value >= portraitScrollState.maxValue - 600) {
            if (!isFeedLoading && !isMoreLoading && repository != null && tracks.isNotEmpty()) {
                isMoreLoading = true
                try {
                    val nextPage = currentPage + 1
                    val existingIds = tracks.map { it.id }.toSet()
                    val activeQuery = if (searchQuery.isNotBlank()) searchQuery else if (selectedCategory != "Hammasi") selectedCategory else ""
                    val newItems = repository.loadMoreTracks(
                        query = activeQuery,
                        page = nextPage,
                        existingIds = existingIds
                    )
                    if (newItems.isNotEmpty()) {
                        tracks = tracks + newItems
                        currentPage = nextPage
                        onAppendQueue(newItems)
                    }
                } catch (e: Exception) {
                } finally {
                    isMoreLoading = false
                }
            }
        }
    }

    val accentColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberNeonBlue
    val screenBg = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) PitchBlack else CyberBg

    val configuration = LocalConfiguration.current
    val isLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(screenBg)
    ) {
        val maxHeight = maxHeight

        if (isLandscape) {
            // =========================================================================
            // LANDSCAPE MODE: Pioneer 2-DIN Avtomobil magnitolasi / Widescreen Dashboard
            // =========================================================================
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                // Chap tomon: Ekran va Trek ma'lumotlari
                Column(
                    modifier = Modifier
                        .weight(1.2f)
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.Center
                ) {
                    TopFasciaBar(
                        accentColor = accentColor,
                        themeStyle = themeStyle,
                        dspSettings = uiState.dspSettings,
                        onToggleTheme = onToggleTheme
                    )
                    Spacer(modifier = Modifier.height(4.dp))

                    if (showMiniVideo) {
                        MiniVideoBezel(
                            track = uiState.currentTrack,
                            themeStyle = themeStyle,
                            onCloseVideo = { showMiniVideo = false },
                            onEnterPip = { }
                        )
                    } else {
                        VfdSpectrumVisualizer(
                            spectrumData = uiState.visualizerData,
                            themeStyle = themeStyle,
                            isPlaying = uiState.isPlaying,
                            modifier = Modifier.height(110.dp)
                        )
                    }

                    Spacer(modifier = Modifier.height(6.dp))

                    TrackInfoCard(
                        uiState = uiState,
                        accentColor = accentColor,
                        themeStyle = themeStyle,
                        onSeek = onSeek
                    )
                }

                // O'ng tomon: Boshqaruv tugmalari va Funksiyalar + Quick Media List
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(DarkFrame, RoundedCornerShape(10.dp))
                            .border(1.dp, MetalBezel, RoundedCornerShape(10.dp))
                            .padding(8.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            IconButton(
                                onClick = {
                                    PioneerSoundEffects.playClick()
                                    onVolumeChange((uiState.volume - 0.05f).coerceIn(0f, 1f))
                                },
                                modifier = Modifier
                                    .size(30.dp)
                                    .background(DarkFrame, RoundedCornerShape(15.dp))
                                    .border(1.dp, MetalBezel, RoundedCornerShape(15.dp))
                            ) {
                                Text("-", color = accentColor, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            }

                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                CarrozzeriaRotaryKnob(
                                    value = uiState.volume,
                                    themeStyle = themeStyle,
                                    onValueChange = onVolumeChange
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    text = "VOL ${(uiState.volume * 40).toInt()}",
                                    color = accentColor,
                                    fontSize = 9.sp,
                                    fontFamily = FontFamily.Monospace,
                                    fontWeight = FontWeight.Bold
                                )
                            }

                            IconButton(
                                onClick = {
                                    PioneerSoundEffects.playClick()
                                    onVolumeChange((uiState.volume + 0.05f).coerceIn(0f, 1f))
                                },
                                modifier = Modifier
                                    .size(30.dp)
                                    .background(DarkFrame, RoundedCornerShape(15.dp))
                                    .border(1.dp, MetalBezel, RoundedCornerShape(15.dp))
                            ) {
                                Text("+", color = accentColor, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            }
                        }

                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            CarAudioButton(icon = Icons.Default.FastRewind, onClick = onPrevious)
                            PlayPauseButton(
                                isPlaying = uiState.isPlaying,
                                isBuffering = uiState.isBuffering,
                                accentColor = accentColor,
                                onClick = onTogglePlayPause
                            )
                            CarAudioButton(icon = Icons.Default.FastForward, onClick = onNext)
                        }
                    }

                    BottomFunctionKeys(
                        accentColor = accentColor,
                        showMiniVideo = showMiniVideo,
                        onNavigateToTrending = onNavigateToTrending,
                        onNavigateToEqualizer = onNavigateToEqualizer,
                        onToggleVideo = { showMiniVideo = !showMiniVideo },
                        onNavigateToSettings = onNavigateToSettings
                    )

                    // Quick Track List in Landscape
                    if (tracks.isNotEmpty()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(DarkFrame, RoundedCornerShape(8.dp))
                                .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
                                .padding(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = "MEDIA TRACKS (${tracks.size})",
                                color = accentColor,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold
                            )
                            tracks.take(12).forEachIndexed { idx, track ->
                                TrackItem(
                                    track = track,
                                    accentColor = accentColor,
                                    onPlay = { onTrackSelect(track, tracks, idx) }
                                )
                            }
                        }
                    }
                }
            }
        } else {
            // =========================================================================
            // PORTRAIT MODE: Tik holatdagi uzun va tepa-pastga tushib chiqadigan oyna
            // =========================================================================
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(portraitScrollState)
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                TopFasciaBar(
                    accentColor = accentColor,
                    themeStyle = themeStyle,
                    dspSettings = uiState.dspSettings,
                    onToggleTheme = onToggleTheme
                )

                Spacer(modifier = Modifier.height(6.dp))

                val visualizerHeight = if (maxHeight < 680.dp) 120.dp else 145.dp
                if (showMiniVideo) {
                    MiniVideoBezel(
                        track = uiState.currentTrack,
                        themeStyle = themeStyle,
                        onCloseVideo = { showMiniVideo = false },
                        onEnterPip = { }
                    )
                } else {
                    VfdSpectrumVisualizer(
                        spectrumData = uiState.visualizerData,
                        themeStyle = themeStyle,
                        isPlaying = uiState.isPlaying,
                        modifier = Modifier.height(visualizerHeight)
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Track Info Screen
                TrackInfoCard(
                    uiState = uiState,
                    accentColor = accentColor,
                    themeStyle = themeStyle,
                    onSeek = onSeek
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Main Pioneer Volume Rotary Knob & Audio Deck Controls
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(DarkFrame, RoundedCornerShape(10.dp))
                        .border(1.dp, MetalBezel, RoundedCornerShape(10.dp))
                        .padding(vertical = 10.dp, horizontal = 14.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        IconButton(
                            onClick = {
                                PioneerSoundEffects.playClick()
                                onVolumeChange((uiState.volume - 0.05f).coerceIn(0f, 1f))
                            },
                            modifier = Modifier
                                .size(34.dp)
                                .background(MetalBezel, RoundedCornerShape(17.dp))
                                .border(1.dp, accentColor.copy(alpha = 0.5f), RoundedCornerShape(17.dp))
                        ) {
                            Text("-", color = accentColor, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        }

                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CarrozzeriaRotaryKnob(
                                value = uiState.volume,
                                themeStyle = themeStyle,
                                onValueChange = onVolumeChange
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = "VOL ${(uiState.volume * 40).toInt()}",
                                color = accentColor,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold
                            )
                        }

                        IconButton(
                            onClick = {
                                PioneerSoundEffects.playClick()
                                onVolumeChange((uiState.volume + 0.05f).coerceIn(0f, 1f))
                            },
                            modifier = Modifier
                                .size(34.dp)
                                .background(MetalBezel, RoundedCornerShape(17.dp))
                                .border(1.dp, accentColor.copy(alpha = 0.5f), RoundedCornerShape(17.dp))
                        ) {
                            Text("+", color = accentColor, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        }
                    }

                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CarAudioButton(icon = Icons.Default.FastRewind, onClick = onPrevious)
                        PlayPauseButton(
                            isPlaying = uiState.isPlaying,
                            isBuffering = uiState.isBuffering,
                            accentColor = accentColor,
                            onClick = onTogglePlayPause
                        )
                        CarAudioButton(icon = Icons.Default.FastForward, onClick = onNext)
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                BottomFunctionKeys(
                    accentColor = accentColor,
                    showMiniVideo = showMiniVideo,
                    onNavigateToTrending = onNavigateToTrending,
                    onNavigateToEqualizer = onNavigateToEqualizer,
                    onToggleVideo = { showMiniVideo = !showMiniVideo },
                    onNavigateToSettings = onNavigateToSettings
                )

                Spacer(modifier = Modifier.height(12.dp))

                // =========================================================================
                // INTEGRATED YOUTUBE SEARCH & LONG SCROLLABLE FEED (Professional YouTube Replica)
                // =========================================================================
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(DarkFrame, RoundedCornerShape(8.dp))
                        .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.TrendingUp, contentDescription = null, tint = OelAmber, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "YOUTUBE PRO FEED",
                            color = OelWhite,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "(${tracks.size})",
                            color = accentColor,
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace
                        )
                    }

                    // Autoplay Toggle Switch Button (Continuous Playback)
                    Row(
                        modifier = Modifier
                            .background(
                                if (uiState.autoplayEnabled) Color(0xFF003844) else Color(0xFF1E2836),
                                RoundedCornerShape(4.dp)
                            )
                            .border(
                                1.dp,
                                if (uiState.autoplayEnabled) OelCyan else Color.Gray,
                                RoundedCornerShape(4.dp)
                            )
                            .clickable {
                                PioneerSoundEffects.playClick()
                                onToggleAutoplay()
                            }
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = if (uiState.autoplayEnabled) "▶ AVTO-IJRO: ON" else "⏸ AVTO-IJRO: OFF",
                            color = if (uiState.autoplayEnabled) OelCyanBright else Color.Gray,
                            fontSize = 9.sp,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // YouTube Style Category Filter Pills
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    items(categories) { cat ->
                        val isSelected = cat == selectedCategory
                        Box(
                            modifier = Modifier
                                .background(
                                    if (isSelected) accentColor else Color(0xFF16202C),
                                    RoundedCornerShape(16.dp)
                                )
                                .border(
                                    1.dp,
                                    if (isSelected) accentColor else MetalBezel,
                                    RoundedCornerShape(16.dp)
                                )
                                .clickable {
                                    PioneerSoundEffects.playClick()
                                    selectedCategory = cat
                                    currentPage = 1
                                    if (repository != null) {
                                        coroutineScope.launch {
                                            isFeedLoading = true
                                            val result = if (cat == "Hammasi" || cat == "Trending") {
                                                repository.getTrendingTracks()
                                            } else {
                                                repository.searchTracks(cat)
                                            }
                                            tracks = result
                                            onAppendQueue(result)
                                            isFeedLoading = false
                                        }
                                    }
                                }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(
                                text = cat,
                                color = if (isSelected) Color.Black else OelWhite,
                                fontSize = 11.sp,
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                fontFamily = FontFamily.SansSerif
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Live YouTube Search Input with Pill Shape
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { query ->
                        searchQuery = query
                        currentPage = 1
                        if (repository != null) {
                            coroutineScope.launch {
                                isFeedLoading = true
                                val result = if (query.isBlank()) {
                                    if (selectedCategory == "Hammasi" || selectedCategory == "Trending") {
                                        repository.getTrendingTracks()
                                    } else {
                                        repository.searchTracks(selectedCategory)
                                    }
                                } else {
                                    repository.searchTracks(query)
                                }
                                tracks = result
                                onAppendQueue(result)
                                isFeedLoading = false
                            }
                        }
                    },
                    placeholder = {
                        Text("YouTube'dan musiqa yoki ijrochini qidirish...", color = Color.Gray, fontSize = 12.sp)
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = null, tint = accentColor, modifier = Modifier.size(20.dp))
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = {
                                PioneerSoundEffects.playClick()
                                searchQuery = ""
                                currentPage = 1
                                if (repository != null) {
                                    coroutineScope.launch {
                                        isFeedLoading = true
                                        val result = repository.getTrendingTracks()
                                        tracks = result
                                        onAppendQueue(result)
                                        isFeedLoading = false
                                    }
                                }
                            }) {
                                Icon(Icons.Default.Clear, contentDescription = "Tozalash", tint = Color.Gray, modifier = Modifier.size(18.dp))
                            }
                        }
                    },
                    shape = RoundedCornerShape(24.dp),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = accentColor,
                        unfocusedBorderColor = MetalBezel,
                        focusedTextColor = OelWhite,
                        unfocusedTextColor = OelWhite,
                        focusedContainerColor = DarkFrame,
                        unfocusedContainerColor = DarkFrame
                    ),
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(10.dp))

                if (isFeedLoading) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(160.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = accentColor, strokeWidth = 2.dp, modifier = Modifier.size(34.dp))
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = "YOUTUBE MA'LUMOTLARI YUKLANMOQDA...",
                                color = accentColor,
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                    }
                } else {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        tracks.forEachIndexed { idx, track ->
                            YouTubeVideoCard(
                                track = track,
                                isCurrentTrack = uiState.currentTrack?.id == track.id,
                                isPlaying = uiState.isPlaying,
                                accentColor = accentColor,
                                onPlay = { onTrackSelect(track, tracks, idx) },
                                onWatchVideo = {
                                    onTrackSelect(track, tracks, idx)
                                    showMiniVideo = true
                                }
                            )
                        }

                        if (isMoreLoading) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 14.dp),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                CircularProgressIndicator(color = accentColor, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = "YANA YOUTUBE VIDEOLARI YUKLANMOQDA...",
                                    color = accentColor,
                                    fontSize = 11.sp,
                                    fontFamily = FontFamily.Monospace,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(28.dp))
            }
        }
    }
}

@Composable
fun TopFasciaBar(
    accentColor: Color,
    themeStyle: CarrozzeriaThemeStyle,
    dspSettings: DspSettings,
    onToggleTheme: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkFrame, RoundedCornerShape(topStart = 8.dp, topEnd = 8.dp))
            .border(1.dp, MetalBezel, RoundedCornerShape(topStart = 8.dp, topEnd = 8.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(
                text = "PIONEER",
                color = Color.LightGray,
                fontSize = 9.sp,
                fontWeight = FontWeight.Light,
                letterSpacing = 2.sp
            )
            Text(
                text = "carrozzeria",
                color = accentColor,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.SansSerif,
                letterSpacing = 1.sp
            )
        }

        // Instant Theme Switch Button
        Box(
            modifier = Modifier
                .background(Color(0xFF16202C), RoundedCornerShape(6.dp))
                .border(1.dp, accentColor, RoundedCornerShape(6.dp))
                .clickable {
                    PioneerSoundEffects.playSuccessBeep()
                    onToggleTheme()
                }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) "🐬 OEL RETRO" else "⚡ CYBER NAVI",
                color = accentColor,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            DspBadge(text = "TUBE", isActive = true, activeColor = OelAmber)
            DspBadge(text = dspSettings.currentPreset.name.take(4), isActive = true, activeColor = accentColor)
            DspBadge(text = "LIVE", isActive = true, activeColor = Color(0xFF00E676))
        }
    }
}

@Composable
fun TrackInfoCard(
    uiState: PlayerUiState,
    accentColor: Color,
    themeStyle: CarrozzeriaThemeStyle,
    onSeek: (Long) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelBg else DarkFrame, RoundedCornerShape(8.dp))
            .border(1.dp, accentColor.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
            .padding(10.dp)
    ) {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "SRC: YOUTUBE AUDIO // HI-FI 320k",
                    color = OelAmber,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = if (uiState.isBuffering) "BUFFERING..." else if (uiState.isPlaying) "PLAYING" else "PAUSED",
                    color = if (uiState.isPlaying) OelCyan else Color.Gray,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }

            Spacer(modifier = Modifier.height(3.dp))

            Text(
                text = uiState.currentTrack?.title ?: "Select music from Trending...",
                color = OelWhite,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Text(
                text = uiState.currentTrack?.artist ?: "Pioneer Carrozzeria Tube Engine",
                color = accentColor,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Spacer(modifier = Modifier.height(6.dp))

            Slider(
                value = uiState.progress,
                onValueChange = { ratio ->
                    PioneerSoundEffects.playKnobTick()
                    val targetMs = (ratio * uiState.durationMs).toLong()
                    onSeek(targetMs)
                },
                colors = SliderDefaults.colors(
                    thumbColor = accentColor,
                    activeTrackColor = accentColor,
                    inactiveTrackColor = Color(0xFF1E2836)
                ),
                modifier = Modifier.height(14.dp)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                val currentSec = uiState.positionMs / 1000
                val totalSec = uiState.durationMs / 1000
                Text(
                    text = String.format("%02d:%02d", currentSec / 60, currentSec % 60),
                    color = OelCyanBright,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    text = String.format("%02d:%02d", totalSec / 60, totalSec % 60),
                    color = Color.LightGray,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
fun PlayPauseButton(
    isPlaying: Boolean,
    isBuffering: Boolean,
    accentColor: Color,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(54.dp)
            .background(MetalBezel, RoundedCornerShape(27.dp))
            .border(2.dp, accentColor, RoundedCornerShape(27.dp))
            .clickable {
                PioneerSoundEffects.playClick()
                onClick()
            },
        contentAlignment = Alignment.Center
    ) {
        if (isBuffering) {
            CircularProgressIndicator(
                color = accentColor,
                strokeWidth = 2.dp,
                modifier = Modifier.size(24.dp)
            )
        } else {
            Icon(
                imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                contentDescription = "Play/Pause",
                tint = OelWhite,
                modifier = Modifier.size(30.dp)
            )
        }
    }
}

@Composable
fun BottomFunctionKeys(
    accentColor: Color,
    showMiniVideo: Boolean,
    onNavigateToTrending: () -> Unit,
    onNavigateToEqualizer: () -> Unit,
    onToggleVideo: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MetalBezel, RoundedCornerShape(8.dp))
            .padding(6.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        FunctionKey(
            title = "TREND",
            icon = Icons.Default.TrendingUp,
            onClick = onNavigateToTrending,
            accentColor = accentColor
        )
        FunctionKey(
            title = "EQ/DSP",
            icon = Icons.Default.Equalizer,
            onClick = onNavigateToEqualizer,
            accentColor = accentColor
        )
        FunctionKey(
            title = if (showMiniVideo) "OEL VFD" else "V-OUT",
            icon = Icons.Default.OndemandVideo,
            onClick = onToggleVideo,
            accentColor = if (showMiniVideo) OelAmber else accentColor
        )
        FunctionKey(
            title = "SETTINGS",
            icon = Icons.Default.Settings,
            onClick = onNavigateToSettings,
            accentColor = accentColor
        )
    }
}

@Composable
fun DspBadge(text: String, isActive: Boolean, activeColor: Color) {
    Box(
        modifier = Modifier
            .background(if (isActive) activeColor.copy(alpha = 0.2f) else Color.Transparent, RoundedCornerShape(3.dp))
            .border(1.dp, if (isActive) activeColor else Color(0xFF263238), RoundedCornerShape(3.dp))
            .padding(horizontal = 4.dp, vertical = 1.dp)
    ) {
        Text(
            text = text,
            color = if (isActive) activeColor else Color(0xFF546E7A),
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun CarAudioButton(icon: ImageVector, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(42.dp)
            .background(DarkFrame, RoundedCornerShape(21.dp))
            .border(1.dp, MetalBezel, RoundedCornerShape(21.dp))
            .clickable {
                PioneerSoundEffects.playClick()
                onClick()
            },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = OelWhite,
            modifier = Modifier.size(22.dp)
        )
    }
}

@Composable
fun FunctionKey(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .clickable {
                PioneerSoundEffects.playClick()
                onClick()
            }
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = title,
            tint = accentColor,
            modifier = Modifier.size(19.dp)
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = title,
            color = OelWhite,
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold
        )
    }
}

/**
 * Authentic Professional YouTube Replica Video Card
 * Features: 16:9 Thumbnail, duration badge, status badge, channel avatar,
 * title, view count, and dedicated Play Audio & Watch Video action buttons.
 */
@Composable
fun YouTubeVideoCard(
    track: Track,
    isCurrentTrack: Boolean,
    isPlaying: Boolean,
    accentColor: Color,
    onPlay: () -> Unit,
    onWatchVideo: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkFrame, RoundedCornerShape(12.dp))
            .border(
                width = if (isCurrentTrack) 1.5.dp else 1.dp,
                color = if (isCurrentTrack) accentColor else MetalBezel,
                shape = RoundedCornerShape(12.dp)
            )
            .clip(RoundedCornerShape(12.dp))
            .clickable {
                PioneerSoundEffects.playClick()
                onPlay()
            }
            .padding(10.dp)
    ) {
        // 1. YouTube 16:9 Thumbnail with Duration Badge and Status Overlay
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(165.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Black)
        ) {
            AsyncImage(
                model = track.thumbnailUrl,
                contentDescription = track.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )

            // Duration Badge (Bottom-Right)
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(6.dp)
                    .background(Color(0xE0000000), RoundedCornerShape(4.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = track.formattedDuration,
                    color = Color.White,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold
                )
            }

            // Playing Badge (Top-Left)
            if (isCurrentTrack) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(6.dp)
                        .background(accentColor.copy(alpha = 0.9f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = if (isPlaying) "▶ O'YNAYAPTI" else "⏸ TO'XTATILGAN",
                        color = Color.Black,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        // 2. Video Details Row (Avatar + Title/Metadata + Actions)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top
        ) {
            // Channel Avatar Circle
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF00838F), Color(0xFF00E5FF))),
                        RoundedCornerShape(19.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = track.artist.take(1).uppercase(),
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(modifier = Modifier.width(10.dp))

            // Title & Channel info
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = track.title,
                    color = if (isCurrentTrack) accentColor else OelWhite,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.SansSerif,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = "${track.artist} • ${track.viewCount} views",
                    color = Color.LightGray,
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Spacer(modifier = Modifier.width(6.dp))

            // Action Buttons: Play Audio & Watch Video
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // Play Audio Button
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .background(MetalBezel, RoundedCornerShape(18.dp))
                        .border(1.dp, accentColor.copy(alpha = 0.5f), RoundedCornerShape(18.dp))
                        .clickable {
                            PioneerSoundEffects.playClick()
                            onPlay()
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isCurrentTrack && isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play",
                        tint = accentColor,
                        modifier = Modifier.size(20.dp)
                    )
                }

                // Watch Video Button
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .background(Color(0xFF003844), RoundedCornerShape(18.dp))
                        .border(1.dp, OelCyan, RoundedCornerShape(18.dp))
                        .clickable {
                            PioneerSoundEffects.playClick()
                            onWatchVideo()
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.OndemandVideo,
                        contentDescription = "Video",
                        tint = OelCyan,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
        }
    }
}
