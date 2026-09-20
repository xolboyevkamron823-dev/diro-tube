package com.carrozzeria.tube.core.youtube

import com.carrozzeria.tube.core.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

/**
 * High-performance YouTube Search and Audio Stream Extraction Engine
 */
class YouTubeRepository {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    // Verified real YouTube hits
    private val defaultTrendingTracks = listOf(
        Track(
            id = "YzQknv9Z9y8",
            title = "Janob Rasul - 90-60 (Original Track)",
            artist = "Janob Rasul",
            durationSec = 244,
            thumbnailUrl = "https://img.youtube.com/vi/YzQknv9Z9y8/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "93M",
            isTrending = true
        ),
        Track(
            id = "Z-slC0Q1bY0",
            title = "Janob Rasul - Sop-sori (Captiva)",
            artist = "Janob Rasul",
            durationSec = 232,
            thumbnailUrl = "https://img.youtube.com/vi/Z-slC0Q1bY0/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "53M",
            isTrending = true
        ),
        Track(
            id = "cjfubjKjQ_M",
            title = "Sherali Jo'rayev - Inson o'zing",
            artist = "Sherali Jo'rayev",
            durationSec = 438,
            thumbnailUrl = "https://img.youtube.com/vi/cjfubjKjQ_M/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "3.9M",
            isTrending = true
        ),
        Track(
            id = "Fd-8YwUR8Ss",
            title = "Sherali Jo'rayev - O'zbegim",
            artist = "Sherali Jo'rayev",
            durationSec = 813,
            thumbnailUrl = "https://img.youtube.com/vi/Fd-8YwUR8Ss/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "41M",
            isTrending = true
        ),
        Track(
            id = "Q17m68V8K6E",
            title = "Yulduz Usmonova - Muhabbat",
            artist = "Yulduz Usmonova",
            durationSec = 280,
            thumbnailUrl = "https://img.youtube.com/vi/Q17m68V8K6E/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "15M",
            isTrending = true
        ),
        Track(
            id = "C456IczY9uc",
            title = "Xurshid Rasulov - Esingdamu",
            artist = "Xurshid Rasulov",
            durationSec = 295,
            thumbnailUrl = "https://img.youtube.com/vi/C456IczY9uc/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "9.1M",
            isTrending = true
        ),
        Track(
            id = "b7fgRbLwlgc",
            title = "Rustam G'oipov - Qora Sochi Jamalak",
            artist = "Rustam G'oipov",
            durationSec = 525,
            thumbnailUrl = "https://img.youtube.com/vi/b7fgRbLwlgc/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "7.4M",
            isTrending = true
        ),
        Track(
            id = "kJQP7kiw5Fk",
            title = "Luis Fonsi - Despacito ft. Daddy Yankee",
            artist = "Luis Fonsi",
            durationSec = 282,
            thumbnailUrl = "https://img.youtube.com/vi/kJQP7kiw5Fk/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "8.3B",
            isTrending = true
        ),
        Track(
            id = "JGwWNGJdvx8",
            title = "Ed Sheeran - Shape of You",
            artist = "Ed Sheeran",
            durationSec = 263,
            thumbnailUrl = "https://img.youtube.com/vi/JGwWNGJdvx8/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "6.1B",
            isTrending = true
        ),
        Track(
            id = "fJ9rUzIMcZQ",
            title = "Queen - Bohemian Rhapsody",
            artist = "Queen",
            durationSec = 360,
            thumbnailUrl = "https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg",
            audioStreamUrl = "",
            viewCount = "1.7B",
            isTrending = true
        )
    )

    private val streamClient = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS)
        .build()

    private val invidiousMirrors = listOf(
        "https://invidious.f5.si",
        "https://invidious.tiekoetter.com",
        "https://inv.nadeko.net"
    )

    suspend fun getTrendingTracks(): List<Track> = withContext(Dispatchers.IO) {
        val result = searchTracks("top uzbek music 2026")
        if (result.isNotEmpty() && result.size > 3) {
            return@withContext result
        }
        return@withContext defaultTrendingTracks
    }

    suspend fun searchTracks(query: String): List<Track> = withContext(Dispatchers.IO) {
        if (query.isBlank()) return@withContext defaultTrendingTracks

        val encoded = URLEncoder.encode(query, "UTF-8")

        // 1. Direct YouTube Web Search (Ultra-fast, 100% genuine results)
        try {
            val ytUrl = "https://www.youtube.com/results?search_query=$encoded"
            val request = Request.Builder()
                .url(ytUrl)
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")
                .header("Accept-Language", "uz,en;q=0.9,ru;q=0.8")
                .build()
            val response = httpClient.newCall(request).execute()
            if (response.isSuccessful) {
                val html = response.body?.string() ?: ""
                val items = parseYouTubeHtml(html)
                if (items.isNotEmpty()) {
                    return@withContext items
                }
            }
        } catch (e: Exception) {
            // Fallback
        }

        // 2. Try Invidious Mirrors
        for (mirror in invidiousMirrors) {
            try {
                val url = "$mirror/api/v1/search?q=$encoded&type=video"
                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0")
                    .build()
                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val items = parseInvidiousJson(body)
                    if (items.isNotEmpty()) {
                        return@withContext items
                    }
                }
            } catch (e: Exception) {
                // Try next mirror
            }
        }

        // 3. Filter default tracks as offline fallback
        val filtered = defaultTrendingTracks.filter {
            it.title.contains(query, ignoreCase = true) || it.artist.contains(query, ignoreCase = true)
        }
        if (filtered.isNotEmpty()) return@withContext filtered

        return@withContext defaultTrendingTracks
    }

    suspend fun getAudioStreamUrl(videoId: String): String = withContext(Dispatchers.IO) {
        // 1. Try Piped API (Direct GoogleVideo high-speed CDN audio streams)
        val pipedInstances = listOf(
            "https://pipedapi.kavin.rocks",
            "https://api.piped.privacy.com.de",
            "https://piped-api.lunar.icu"
        )
        for (piped in pipedInstances) {
            try {
                val url = "$piped/streams/$videoId"
                val request = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0").build()
                val response = streamClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val root = JSONObject(body)
                    if (root.has("audioStreams")) {
                        val arr = root.getJSONArray("audioStreams")
                        for (i in 0 until arr.length()) {
                            val stream = arr.getJSONObject(i)
                            val sUrl = stream.optString("url", "")
                            val mime = stream.optString("mimeType", "")
                            if (sUrl.isNotBlank() && (mime.contains("audio/mp4") || mime.contains("audio/m4a"))) {
                                return@withContext sUrl
                            }
                        }
                    }
                }
            } catch (e: Exception) { }
        }

        // 2. Try Invidious Mirrors
        for (mirror in invidiousMirrors) {
            try {
                val url = "$mirror/api/v1/videos/$videoId"
                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    .build()
                val response = streamClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val root = JSONObject(body)
                    if (root.has("adaptiveFormats")) {
                        val arr = root.getJSONArray("adaptiveFormats")
                        var bestUrl = ""
                        for (i in 0 until arr.length()) {
                            val f = arr.getJSONObject(i)
                            val type = f.optString("type", "")
                            val streamUrl = f.optString("url", "")
                            val itag = f.optInt("itag", 0)
                            if (type.contains("audio") && streamUrl.isNotBlank()) {
                                if (itag == 140 || type.contains("mp4")) {
                                    return@withContext streamUrl
                                }
                                if (bestUrl.isBlank()) bestUrl = streamUrl
                            }
                        }
                        if (bestUrl.isNotBlank()) return@withContext bestUrl
                    }
                }
            } catch (e: Exception) {
                // Try next mirror
            }
        }
        // Direct stream proxy
        return@withContext "https://invidious.f5.si/latest_version?id=$videoId&itag=140"
    }

    suspend fun loadMoreTracks(query: String, page: Int, existingIds: Set<String>): List<Track> = withContext(Dispatchers.IO) {
        val q = if (query.isNotBlank()) {
            when (page % 4) {
                1 -> "$query official"
                2 -> "$query remix"
                3 -> "$query live"
                else -> "$query full"
            }
        } else {
            when (page % 5) {
                1 -> "uzbek music 2026 yangi"
                2 -> "top uzbek hits"
                3 -> "sherali jo'rayev yulduz usmonova"
                4 -> "jonli ijro musiqa"
                else -> "bass klip uzbek estrada"
            }
        }
        val encoded = URLEncoder.encode(q, "UTF-8")

        // 1. Try Invidious with page param
        for (mirror in invidiousMirrors) {
            try {
                val url = "$mirror/api/v1/search?q=$encoded&type=video&page=$page"
                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0")
                    .build()
                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val items = parseInvidiousJson(body).filter { !existingIds.contains(it.id) }
                    if (items.isNotEmpty()) {
                        return@withContext items
                    }
                }
            } catch (e: Exception) { }
        }

        // 2. Fallback to direct YouTube HTML search with query variant
        try {
            val ytUrl = "https://www.youtube.com/results?search_query=$encoded"
            val request = Request.Builder()
                .url(ytUrl)
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")
                .header("Accept-Language", "uz,en;q=0.9,ru;q=0.8")
                .build()
            val response = httpClient.newCall(request).execute()
            if (response.isSuccessful) {
                val html = response.body?.string() ?: ""
                val items = parseYouTubeHtml(html).filter { !existingIds.contains(it.id) }
                if (items.isNotEmpty()) {
                    return@withContext items
                }
            }
        } catch (e: Exception) { }

        return@withContext emptyList()
    }

    private fun parseInvidiousJson(json: String): List<Track> {
        val list = mutableListOf<Track>()
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length().coerceAtMost(50)) {
                val obj = arr.getJSONObject(i)
                val type = obj.optString("type", "video")
                if (type != "video") continue

                val videoId = obj.optString("videoId", "")
                if (videoId.isBlank()) continue

                val title = obj.optString("title", "YouTube Track")
                val author = obj.optString("author", "Artist")
                val lengthSec = obj.optLong("lengthSeconds", 220)
                val views = obj.optString("viewCountText", "100K")
                val thumb = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"

                list.add(
                    Track(
                        id = videoId,
                        title = title,
                        artist = author,
                        durationSec = lengthSec,
                        thumbnailUrl = thumb,
                        audioStreamUrl = "",
                        viewCount = views,
                        isTrending = false
                    )
                )
            }
        } catch (e: Exception) {
            // Ignore
        }
        return list
    }

    private fun parseYouTubeHtml(html: String): List<Track> {
        val list = mutableListOf<Track>()
        try {
            val seenIds = mutableSetOf<String>()
            val chunks = html.split("\"videoRenderer\":{\"videoId\":\"", "\"compactVideoRenderer\":{\"videoId\":\"")
            for (i in 1 until chunks.size) {
                if (list.size >= 50) break
                val c = chunks[i]
                if (c.length < 11) continue
                val videoId = c.substring(0, 11)
                if (videoId.contains("\"") || videoId.contains("\\") || !seenIds.add(videoId)) continue

                var title = "Musiqa"
                val titlePattern1 = Pattern.compile("\"title\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"")
                val mTitle1 = titlePattern1.matcher(c)
                if (mTitle1.find()) {
                    title = unescapeHtml(mTitle1.group(1) ?: title)
                } else {
                    val titlePattern2 = Pattern.compile("\"title\":\\{\"simpleText\":\"([^\"]+)\"")
                    val mTitle2 = titlePattern2.matcher(c)
                    if (mTitle2.find()) {
                        title = unescapeHtml(mTitle2.group(1) ?: title)
                    }
                }

                var author = "YouTube Artist"
                val authorPattern1 = Pattern.compile("BylineText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"")
                val mAuthor1 = authorPattern1.matcher(c)
                if (mAuthor1.find()) {
                    author = unescapeHtml(mAuthor1.group(1) ?: author)
                } else {
                    val authorPattern2 = Pattern.compile("ownerText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"")
                    val mAuthor2 = authorPattern2.matcher(c)
                    if (mAuthor2.find()) {
                        author = unescapeHtml(mAuthor2.group(1) ?: author)
                    }
                }

                var durationSec = 220L
                val durPattern = Pattern.compile("\"lengthText\":\\{\"simpleText\":\"([^\"]+)\"")
                val mDur = durPattern.matcher(c)
                if (mDur.find()) {
                    val durStr = mDur.group(1) ?: "03:40"
                    val parts = durStr.split(":")
                    if (parts.size == 2) {
                        durationSec = (parts[0].toLongOrNull() ?: 3) * 60 + (parts[1].toLongOrNull() ?: 40)
                    } else if (parts.size == 3) {
                        durationSec = (parts[0].toLongOrNull() ?: 0) * 3600 + (parts[1].toLongOrNull() ?: 3) * 60 + (parts[2].toLongOrNull() ?: 40)
                    }
                }

                var views = "1M"
                val viewPattern = Pattern.compile("\"viewCountText\":\\{\"simpleText\":\"([^\"]+)\"")
                val mView = viewPattern.matcher(c)
                if (mView.find()) {
                    views = (mView.group(1) ?: "1M").replace(" views", "").replace(" marta", "")
                } else {
                    val viewPattern2 = Pattern.compile("\"shortViewCountText\":\\{\"simpleText\":\"([^\"]+)\"")
                    val mView2 = viewPattern2.matcher(c)
                    if (mView2.find()) {
                        views = (mView2.group(1) ?: "1M").replace(" views", "").replace(" marta", "")
                    }
                }

                list.add(
                    Track(
                        id = videoId,
                        title = title,
                        artist = author,
                        durationSec = durationSec,
                        thumbnailUrl = "https://img.youtube.com/vi/$videoId/hqdefault.jpg",
                        audioStreamUrl = "",
                        viewCount = views,
                        isTrending = false
                    )
                )
            }
        } catch (e: Exception) {
            // Ignore
        }
        return list
    }

    private fun unescapeHtml(str: String): String {
        return try {
            str.replace("\\u0026", "&")
               .replace("\\\"", "\"")
               .replace("\\'", "'")
               .replace("\\\\", "\\")
        } catch (e: Exception) {
            str
        }
    }

    suspend fun getRelatedTracks(videoId: String, title: String): List<Track> = withContext(Dispatchers.IO) {
        for (mirror in invidiousMirrors) {
            try {
                val url = "$mirror/api/v1/videos/$videoId"
                val request = Request.Builder()
                    .url(url)
                    .header("User-Agent", "Mozilla/5.0")
                    .build()
                val response = streamClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val root = JSONObject(body)
                    if (root.has("recommendedVideos")) {
                        val arr = root.getJSONArray("recommendedVideos")
                        val list = mutableListOf<Track>()
                        for (i in 0 until arr.length().coerceAtMost(15)) {
                            val obj = arr.getJSONObject(i)
                            val vid = obj.optString("videoId", "")
                            val t = obj.optString("title", "")
                            val a = obj.optString("author", "")
                            val d = obj.optLong("lengthSeconds", 200)
                            val v = obj.optString("viewCountText", "1M")
                            if (vid.isNotBlank() && t.isNotBlank()) {
                                list.add(
                                    Track(
                                        id = vid,
                                        title = t,
                                        artist = a,
                                        durationSec = d,
                                        thumbnailUrl = "https://img.youtube.com/vi/$vid/hqdefault.jpg",
                                        viewCount = v
                                    )
                                )
                            }
                        }
                        if (list.isNotEmpty()) return@withContext list
                    }
                }
            } catch (e: Exception) { }
        }

        val artistPart = title.split("-", "—", "ft.", "feat.").firstOrNull()?.trim() ?: title
        val fallback = searchTracks("$artistPart music")
        if (fallback.isNotEmpty()) return@withContext fallback

        return@withContext defaultTrendingTracks
    }
}
