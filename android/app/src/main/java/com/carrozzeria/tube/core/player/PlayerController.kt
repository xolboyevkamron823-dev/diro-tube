package com.carrozzeria.tube.core.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.carrozzeria.tube.core.model.PlayerUiState
import com.carrozzeria.tube.core.model.Track
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.random.Random

import com.carrozzeria.tube.core.youtube.YouTubeRepository
import kotlinx.coroutines.withContext

/**
 * Controller connecting Jetpack Compose UI to CarrozzeriaPlaybackService
 */
class PlayerController(
    private val context: Context,
    private val repository: YouTubeRepository = YouTubeRepository()
) {

    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var mediaController: MediaController? = null

    private val _uiState = MutableStateFlow(PlayerUiState())
    val uiState: StateFlow<PlayerUiState> = _uiState.asStateFlow()

    private val queue = mutableListOf<Track>()
    private var currentQueueIndex = -1
    private var progressTrackerJob: Job? = null

    init {
        initController()
        startVisualizerGenerator()
    }

    private fun initController() {
        val sessionToken = SessionToken(
            context,
            ComponentName(context, CarrozzeriaPlaybackService::class.java)
        )
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            mediaController = controllerFuture?.get()
            setupPlayerListener()
        }, MoreExecutors.directExecutor())
    }

    private fun setupPlayerListener() {
        mediaController?.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _uiState.update { it.copy(isPlaying = isPlaying) }
                if (isPlaying) {
                    startProgressTracker()
                } else {
                    stopProgressTracker()
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                val isBuffering = playbackState == Player.STATE_BUFFERING
                _uiState.update { it.copy(isBuffering = isBuffering) }

                if (playbackState == Player.STATE_READY) {
                    val duration = mediaController?.duration?.coerceAtLeast(0) ?: 0
                    _uiState.update { it.copy(durationMs = duration) }
                } else if (playbackState == Player.STATE_ENDED) {
                    playNext()
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                _uiState.update { it.copy(isBuffering = false) }
                android.util.Log.e("PlayerController", "ExoPlayer playback error: ${error.errorCodeName}", error)
            }
        })
    }

    fun setQueueAndPlay(tracks: List<Track>, startIndex: Int = 0) {
        if (tracks.isEmpty()) return
        queue.clear()
        queue.addAll(tracks)
        currentQueueIndex = startIndex.coerceIn(0, queue.size - 1)
        playTrackInternal(queue[currentQueueIndex])
    }

    fun appendQueue(newTracks: List<Track>) {
        val fresh = newTracks.filter { n -> !queue.any { it.id == n.id } }
        queue.addAll(fresh)
    }

    fun playTrack(track: Track) {
        val existingIndex = queue.indexOfFirst { it.id == track.id }
        if (existingIndex >= 0) {
            currentQueueIndex = existingIndex
        } else {
            queue.add(track)
            currentQueueIndex = queue.size - 1
        }
        playTrackInternal(track)
    }

    private fun playTrackInternal(track: Track) {
        _uiState.update {
            it.copy(
                currentTrack = track,
                positionMs = 0,
                durationMs = track.durationSec * 1000,
                isBuffering = true
            )
        }

        scope.launch(Dispatchers.IO) {
            val urlToPlay = if (track.audioStreamUrl.startsWith("http") && !track.audioStreamUrl.contains("codeskulptor")) {
                track.audioStreamUrl
            } else {
                repository.getAudioStreamUrl(track.id)
            }

            withContext(Dispatchers.Main) {
                val controller = mediaController ?: return@withContext
                val mediaItem = MediaItem.Builder()
                    .setUri(urlToPlay)
                    .setMediaMetadata(
                        MediaMetadata.Builder()
                            .setTitle(track.title)
                            .setArtist(track.artist)
                            .setDisplayTitle(track.title)
                            .build()
                    )
                    .build()

                controller.setMediaItem(mediaItem)
                controller.prepare()
                controller.play()
            }

            // Pre-fetch related tracks if queue is short so next track is always ready
            if (queue.size - currentQueueIndex < 3) {
                try {
                    val related = repository.getRelatedTracks(track.id, track.title)
                    withContext(Dispatchers.Main) {
                        val fresh = related.filter { r -> !queue.any { it.id == r.id } }
                        queue.addAll(fresh)
                    }
                } catch (e: Exception) { }
            }
        }
    }

    fun toggleAutoplay() {
        _uiState.update { it.copy(autoplayEnabled = !it.autoplayEnabled) }
    }

    fun togglePlayPause() {
        val controller = mediaController ?: return
        if (controller.isPlaying) {
            controller.pause()
        } else {
            controller.play()
        }
    }

    fun playNext() {
        if (!_uiState.value.autoplayEnabled && currentQueueIndex + 1 >= queue.size) {
            return
        }

        if (queue.isNotEmpty() && currentQueueIndex + 1 < queue.size) {
            currentQueueIndex++
            playTrackInternal(queue[currentQueueIndex])
        } else if (queue.isNotEmpty()) {
            val current = queue.getOrNull(currentQueueIndex)
            scope.launch(Dispatchers.IO) {
                val related = if (current != null) {
                    repository.getRelatedTracks(current.id, current.title)
                } else {
                    repository.getTrendingTracks()
                }
                withContext(Dispatchers.Main) {
                    val fresh = related.filter { r -> !queue.any { it.id == r.id } }
                    if (fresh.isNotEmpty()) {
                        val nextIdx = queue.size
                        queue.addAll(fresh)
                        currentQueueIndex = nextIdx
                        playTrackInternal(queue[currentQueueIndex])
                    } else if (queue.isNotEmpty()) {
                        currentQueueIndex = 0
                        playTrackInternal(queue[0])
                    }
                }
            }
        }
    }

    fun playPrevious() {
        if (queue.isNotEmpty() && currentQueueIndex - 1 >= 0) {
            currentQueueIndex--
            playTrackInternal(queue[currentQueueIndex])
        }
    }

    fun seekTo(positionMs: Long) {
        mediaController?.seekTo(positionMs)
        _uiState.update { it.copy(positionMs = positionMs) }
    }

    fun setVolume(volume: Float) {
        val clamped = volume.coerceIn(0f, 1f)
        mediaController?.volume = clamped
        _uiState.update { it.copy(volume = clamped) }
    }

    private fun startProgressTracker() {
        stopProgressTracker()
        progressTrackerJob = scope.launch {
            while (isActive) {
                mediaController?.let { controller ->
                    if (controller.isPlaying) {
                        val currentPos = controller.currentPosition.coerceAtLeast(0)
                        val totalDur = controller.duration.coerceAtLeast(0)
                        _uiState.update {
                            it.copy(
                                positionMs = currentPos,
                                durationMs = if (totalDur > 0) totalDur else it.durationMs
                            )
                        }
                    }
                }
                delay(250)
            }
        }
    }

    private fun stopProgressTracker() {
        progressTrackerJob?.cancel()
        progressTrackerJob = null
    }

    /**
     * Pioneer Carrozzeria VFD animated spectrum bars simulation.
     * Reacts to playback state and frequency energy!
     */
    private fun startVisualizerGenerator() {
        scope.launch {
            val bars = FloatArray(16) { 0.05f }
            while (isActive) {
                if (_uiState.value.isPlaying) {
                    for (i in bars.indices) {
                        // Bass frequencies have more punch, higher bands flutter
                        val baseWeight = if (i < 4) 0.7f else if (i < 10) 0.5f else 0.4f
                        val randomTarget = Random.nextFloat() * baseWeight + 0.15f
                        bars[i] = (bars[i] * 0.4f + randomTarget * 0.6f).coerceIn(0.08f, 0.98f)
                    }
                } else {
                    for (i in bars.indices) {
                        bars[i] = (bars[i] * 0.85f).coerceAtLeast(0.02f)
                    }
                }
                _uiState.update { it.copy(visualizerData = bars.copyOf()) }
                delay(60) // ~16 FPS smooth OEL/VFD refresh
            }
        }
    }

    fun release() {
        stopProgressTracker()
        mediaController?.let {
            MediaController.releaseFuture(controllerFuture!!)
        }
    }
}
