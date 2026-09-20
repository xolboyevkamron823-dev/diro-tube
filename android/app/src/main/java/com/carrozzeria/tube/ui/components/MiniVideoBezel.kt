package com.carrozzeria.tube.ui.components

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.carrozzeria.tube.core.audiofx.PioneerSoundEffects
import com.carrozzeria.tube.core.model.Track
import com.carrozzeria.tube.ui.theme.CarrozzeriaThemeStyle
import com.carrozzeria.tube.ui.theme.CyberAccentAmber
import com.carrozzeria.tube.ui.theme.CyberBg
import com.carrozzeria.tube.ui.theme.CyberNeonBlue
import com.carrozzeria.tube.ui.theme.MetalBezel
import com.carrozzeria.tube.ui.theme.OelBg
import com.carrozzeria.tube.ui.theme.OelCyan
import com.carrozzeria.tube.ui.theme.OelWhite

/**
 * Pioneer Carrozzeria V-OUT Live YouTube Video Monitor Bezel
 * Plays full YouTube videos without Error 150/152 restrictions using dual IFrame + Mobile Web fallback.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MiniVideoBezel(
    track: Track?,
    themeStyle: CarrozzeriaThemeStyle,
    onCloseVideo: () -> Unit,
    onEnterPip: () -> Unit,
    modifier: Modifier = Modifier
) {
    val borderColor = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan.copy(alpha = 0.7f) else CyberNeonBlue
    val bezelBg = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelBg else CyberBg
    val context = LocalContext.current

    var isWebViewSoundEnabled by remember { mutableStateOf(false) }
    var lastLoadedVideoId by remember { mutableStateOf("") }

    val webView = remember {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(AndroidColor.BLACK)

            try {
                val cookieManager = CookieManager.getInstance()
                cookieManager.setAcceptCookie(true)
                cookieManager.setAcceptThirdPartyCookies(this, true)
            } catch (e: Exception) { }

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                mediaPlaybackRequiresUserGesture = false
                loadWithOverviewMode = true
                useWideViewPort = true
                builtInZoomControls = false
                displayZoomControls = false
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                // Chrome Mobile User-Agent
                userAgentString = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
            }
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    // Keep navigation inside WebView
                    return false
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    // When on m.youtube.com, hide surrounding UI and make video fill bezel
                    if (url != null && url.contains("youtube.com/watch")) {
                        val injectCssAndPlay = """
                            javascript:(function() {
                                var s = document.createElement('style');
                                s.innerHTML = 'header, #header-bar, ytm-pivot-bar-renderer, ytm-item-section-renderer, #related, .watch-below-the-player, ytm-comment-section-renderer, .engagement-panel, ytm-mobile-topbar-renderer { display: none !important; } html, body { background: #000 !important; overflow: hidden !important; } .player-container, #player-control-overlay, video { position: fixed !important; top:0 !important; left:0 !important; width:100% !important; height:100% !important; z-index:999999 !important; object-fit:contain !important; }';
                                document.head.appendChild(s);
                                var v = document.querySelector('video');
                                if (v) {
                                    v.muted = true;
                                    v.play();
                                }
                            })()
                        """.trimIndent()
                        view?.evaluateJavascript(injectCssAndPlay, null)
                    }
                }
            }
        }
    }

    // Load new video when track id changes
    LaunchedEffect(track?.id) {
        val vid = track?.id
        if (!vid.isNullOrBlank() && vid != lastLoadedVideoId) {
            lastLoadedVideoId = vid
            val playerHtml = """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                    <style>
                        * { margin:0; padding:0; box-sizing:border-box; background:#000000; }
                        html, body, #player-container { width:100%; height:100%; overflow:hidden; background:#000000; }
                        iframe { width:100%; height:100%; border:none; }
                    </style>
                </head>
                <body>
                    <div id="player-container">
                        <iframe id="ytplayer"
                            src="https://www.youtube.com/embed/$vid?autoplay=1&playsinline=1&enablejsapi=1&rel=0&modestbranding=1&fs=0&controls=1&mute=1&origin=https://www.youtube.com"
                            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                            allowfullscreen>
                        </iframe>
                    </div>
                    <script>
                        // Listen for embed errors (101, 150, 152) and auto-switch to Mobile YouTube
                        window.addEventListener('message', function(event) {
                            try {
                                var data = JSON.parse(event.data);
                                if (data.event === 'onError' && (data.info === 101 || data.info === 150 || data.info === 152 || data.info === 2)) {
                                    window.location.replace("https://m.youtube.com/watch?v=$vid&autoplay=1");
                                }
                            } catch (e) {}
                        });
                        // Fallback timeout: if iframe doesn't start, redirect to official mobile watch page
                        setTimeout(function() {
                            var iframe = document.getElementById('ytplayer');
                            if (!iframe) {
                                window.location.replace("https://m.youtube.com/watch?v=$vid&autoplay=1");
                            }
                        }, 4000);
                    </script>
                </body>
                </html>
            """.trimIndent()
            webView.loadDataWithBaseURL("https://www.youtube.com", playerHtml, "text/html", "UTF-8", "https://www.youtube.com")
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            try {
                webView.stopLoading()
                webView.loadUrl("about:blank")
                webView.destroy()
            } catch (e: Exception) { }
        }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MetalBezel, RoundedCornerShape(10.dp))
            .border(2.dp, borderColor, RoundedCornerShape(10.dp))
            .padding(6.dp)
    ) {
        // Carrozzeria Bezel Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 6.dp, vertical = 3.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.OndemandVideo,
                    contentDescription = null,
                    tint = if (themeStyle == CarrozzeriaThemeStyle.CLASSIC_OEL) OelCyan else CyberAccentAmber,
                    modifier = Modifier.size(15.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "V-OUT // YOUTUBE LIVE",
                    color = OelWhite,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                // Audio Routing Indicator
                Box(
                    modifier = Modifier
                        .background(Color(0xFF142436), RoundedCornerShape(4.dp))
                        .border(1.dp, OelCyan.copy(alpha = 0.5f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "🔊 CARROZZERIA DSP AUDIO",
                        color = OelCyan,
                        fontSize = 8.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold
                    )
                }

                Spacer(modifier = Modifier.width(6.dp))

                // Instant switch to Dolphins
                Row(
                    modifier = Modifier
                        .background(Color(0xFF003844), RoundedCornerShape(4.dp))
                        .border(1.dp, OelCyan, RoundedCornerShape(4.dp))
                        .clickable {
                            PioneerSoundEffects.playClick()
                            onCloseVideo()
                        }
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "🐬 DELFINLAR",
                        color = OelCyan,
                        fontSize = 9.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold
                    )
                }

                Spacer(modifier = Modifier.width(4.dp))

                IconButton(
                    onClick = {
                        PioneerSoundEffects.playClick()
                        onEnterPip()
                    },
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.PictureInPictureAlt,
                        contentDescription = "PIP Mode",
                        tint = OelWhite,
                        modifier = Modifier.size(15.dp)
                    )
                }
                Spacer(modifier = Modifier.width(2.dp))
                IconButton(
                    onClick = {
                        PioneerSoundEffects.playClick()
                        onCloseVideo()
                    },
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close Video",
                        tint = Color(0xFFFF5252),
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        // Screen Area (16:9 Video Monitor)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(bezelBg),
            contentAlignment = Alignment.Center
        ) {
            if (track != null && track.id.isNotBlank()) {
                AndroidView(
                    factory = { webView },
                    modifier = Modifier.fillMaxSize()
                )

                // Subtitle sync badge
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(6.dp)
                        .background(Color(0xEE000000), RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "● LIVE: ${track.title.take(28)}",
                        color = OelCyan,
                        fontSize = 9.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold
                    )
                }
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.clickable {
                        PioneerSoundEffects.playClick()
                        onCloseVideo()
                    }
                ) {
                    Text(
                        text = "🐬 DELFINLAR EKRANI (BOSING)",
                        color = OelCyan,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Video o'ynatilmaganda delfinlar ko'rinadi",
                        color = Color.LightGray,
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}
