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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import com.carrozzeria.tube.core.model.Track
import com.carrozzeria.tube.core.youtube.YouTubeRepository
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CyberAccentAmber
import com.carrozzeria.tube.ui.theme.CyberBg
import com.carrozzeria.tube.ui.theme.CyberNeonBlue
import com.carrozzeria.tube.ui.theme.DarkFrame
import com.carrozzeria.tube.ui.theme.MetalBezel
import com.carrozzeria.tube.ui.theme.OelAmber
import com.carrozzeria.tube.ui.theme.OelBg
import com.carrozzeria.tube.ui.theme.OelCyan
import com.carrozzeria.tube.ui.theme.OelWhite
import com.carrozzeria.tube.ui.theme.PitchBlack
import kotlinx.coroutines.launch

@Composable
fun TrendingScreen(
    repository: YouTubeRepository,
    themeStyle: CarrozzeriaThemeStyle,
    onTrackSelect: (Track) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val coroutineScope = rememberCoroutineScope()
    var tracks by remember { mutableStateOf<List<Track>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var searchQuery by remember { mutableStateOf("") }

    val accentColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberNeonBlue
    val screenBg = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) PitchBlack else CyberBg

    LaunchedEffect(Unit) {
        isLoading = true
        tracks = repository.getTrendingTracks()
        isLoading = false
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(screenBg)
            .padding(12.dp)
    ) {
        // Header
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
                imageVector = Icons.Default.TrendingUp,
                contentDescription = null,
                tint = OelAmber,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column {
                Text(
                    text = "YOUTUBE TRENDING",
                    color = OelWhite,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    text = "TOP MUSIC CHARTS // REGION: UZ/GLOBAL",
                    color = accentColor,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        // Search Bar
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { query ->
                searchQuery = query
                coroutineScope.launch {
                    isLoading = true
                    tracks = repository.searchTracks(query)
                    isLoading = false
                }
            },
            placeholder = {
                Text("Search YouTube music, artists...", color = Color.Gray, fontSize = 12.sp)
            },
            leadingIcon = {
                Icon(Icons.Default.Search, contentDescription = null, tint = accentColor)
            },
            trailingIcon = {
                if (searchQuery.isNotEmpty()) {
                    IconButton(onClick = {
                        PioneerSoundEffects.playClick()
                        searchQuery = ""
                        coroutineScope.launch {
                            isLoading = true
                            tracks = repository.getTrendingTracks()
                            isLoading = false
                        }
                    }) {
                        Icon(Icons.Default.Clear, contentDescription = "Clear", tint = Color.Gray)
                    }
                }
            },
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

        if (isLoading) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = accentColor)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "LOADING CARROZZERIA FEED...",
                        color = accentColor,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                items(tracks) { track ->
                    TrackItem(
                        track = track,
                        accentColor = accentColor,
                        onPlay = { onTrackSelect(track) }
                    )
                }
            }
        }
    }
}

@Composable
fun TrackItem(
    track: Track,
    accentColor: Color,
    onPlay: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkFrame, RoundedCornerShape(8.dp))
            .border(1.dp, MetalBezel, RoundedCornerShape(8.dp))
            .clickable {
                PioneerSoundEffects.playClick()
                onPlay()
            }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Thumbnail / Mini screen
        Box(
            modifier = Modifier
                .size(60.dp, 44.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color.Black)
        ) {
            AsyncImage(
                model = track.thumbnailUrl,
                contentDescription = track.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            // Duration tag
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .background(Color(0xCC000000))
                    .padding(horizontal = 3.dp, vertical = 1.dp)
            ) {
                Text(
                    text = track.formattedDuration,
                    color = Color.White,
                    fontSize = 8.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }

        Spacer(modifier = Modifier.width(10.dp))

        // Info
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = track.title,
                color = OelWhite,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = track.artist,
                color = accentColor,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = "${track.viewCount} views",
                color = Color.Gray,
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace
            )
        }

        // Play Button
        IconButton(
            onClick = {
                PioneerSoundEffects.playClick()
                onPlay()
            },
            modifier = Modifier
                .size(36.dp)
                .background(MetalBezel, RoundedCornerShape(18.dp))
        ) {
            Icon(
                imageVector = Icons.Default.PlayArrow,
                contentDescription = "Play",
                tint = accentColor,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
