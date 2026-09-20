using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;

namespace DiroTube
{
    public partial class MainWindow : Window
    {
        private static readonly HttpClient httpClient = new HttpClient(new HttpClientHandler
        {
            AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate
        });

        private readonly List<CoreWebView2Frame> activeFrames = new List<CoreWebView2Frame>();

        public MainWindow()
        {
            InitializeComponent();
            httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36");
            httpClient.DefaultRequestHeaders.Add("Accept-Language", "uz,en-US;q=0.9,en;q=0.8,ru;q=0.7");
            Loaded += MainWindow_Loaded;
        }

        private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                // Dedicated profile directory to enable security bypass flags reliably
                string userDataFolder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "DiroTube",
                    "WebView2Profile"
                );
                Directory.CreateDirectory(userDataFolder);

                // Disable web security & CORS so Web Audio can directly process raw YouTube video streams
                var options = new CoreWebView2EnvironmentOptions(
                    "--disable-web-security --autoplay-policy=no-user-gesture-required --allow-file-access-from-files"
                );
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder, options);
                await webView.EnsureCoreWebView2Async(env);

                webView.CoreWebView2.Settings.IsWebMessageEnabled = true;
                webView.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = true;
                webView.CoreWebView2.Settings.AreDevToolsEnabled = true;

                try
                {
                    await webView.CoreWebView2.CallDevToolsProtocolMethodAsync("Console.enable", "{}");
                    await webView.CoreWebView2.CallDevToolsProtocolMethodAsync("Runtime.enable", "{}");
                    var receiver = webView.CoreWebView2.GetDevToolsProtocolEventReceiver("Runtime.consoleAPICalled");
                    receiver.DevToolsProtocolEventReceived += (s, args) =>
                    {
                        try
                        {
                            using var cdoc = JsonDocument.Parse(args.ParameterObjectAsJson);
                            var croot = cdoc.RootElement;
                            string type = croot.TryGetProperty("type", out var tp) ? tp.GetString() ?? "log" : "log";
                            string text = "";
                            if (croot.TryGetProperty("args", out var cargs))
                            {
                                foreach (var item in cargs.EnumerateArray())
                                {
                                    if (item.TryGetProperty("value", out var val))
                                        text += val.ToString() + " ";
                                    else if (item.TryGetProperty("description", out var desc))
                                        text += desc.ToString() + " ";
                                }
                            }
                            LogDebug($"[CDP {type}] {text.Trim()}");
                        }
                        catch { }
                    };
                }
                catch { }

                // Handle messages from the UI (e.g. YouTube search)
                webView.CoreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;

                string wwwrootDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "wwwroot");
                if (!Directory.Exists(wwwrootDir))
                {
                    wwwrootDir = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot");
                }

                // Map local folder to standard public HTTPS domain to resolve YouTube Error 152/153
                webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                    "appassets.dirotube.com",
                    wwwrootDir,
                    CoreWebView2HostResourceAccessKind.Allow
                );

                // Ensure YouTube requests have matching, valid origin headers
                webView.CoreWebView2.AddWebResourceRequestedFilter("https://*.youtube.com/*", CoreWebView2WebResourceContext.All);
                webView.CoreWebView2.AddWebResourceRequestedFilter("https://*.youtube-nocookie.com/*", CoreWebView2WebResourceContext.All);
                webView.CoreWebView2.AddWebResourceRequestedFilter("https://*.googlevideo.com/*", CoreWebView2WebResourceContext.All);

                webView.CoreWebView2.WebResourceRequested += (s, args) =>
                {
                    args.Request.Headers.SetHeader("Referer", "https://appassets.dirotube.com/");
                    args.Request.Headers.SetHeader("Origin", "https://appassets.dirotube.com");
                };

                // Track child frames (e.g. YouTube player iframe)
                webView.CoreWebView2.FrameCreated += (s, args) =>
                {
                    var frame = args.Frame;
                    activeFrames.Add(frame);
                    frame.Destroyed += (fs, fargs) =>
                    {
                        activeFrames.Remove(frame);
                    };
                };

                // Inject Pioneer Carrozzeria DSP, Equalizer, and Sound Field Control (SFC) engine
                await webView.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(@"
(function() {
    let audioCtx = null;
    let hookedVideo = null;
    let sourceNode = null;
    let eqFilters = [];
    let bassFilter = null;
    let asrFilter = null;
    let loudFilter = null;
    let convolver = null;
    let wetGainNode = null;
    let dryGainNode = null;
    let hallBuffer = null;
    let clubBuffer = null;
    let stageBuffer = null;

    let currentDspState = {
        liveMode: 'HALL',
        presetName: 'POWERFUL',
        eqGains: [8, 5, 0, 0, 4, 6, 7],
        bassBoost: 6,
        asr: true,
        loud: true,
        volume: 100
    };

    function sendLog(txt) {
        try {
            if (window.chrome && window.chrome.webview) {
                window.chrome.webview.postMessage({ action: 'IFRAME_LOG', text: window.location.hostname + ': ' + txt });
            }
        } catch(e) {}
        try {
            window.parent.postMessage({ action: 'IFRAME_LOG', text: window.location.hostname + ': ' + txt }, '*');
        } catch(e) {}
    }

    sendLog('Injected DSP script active in: ' + window.location.href);

    // Pioneer Carrozzeria SFC: Physical Schroeder-Moorer Acoustic Reverb Generator
    function buildImpulseResponse(ctx, durationSec, roomSize, damping, preDelaySec) {
        const rate = ctx.sampleRate;
        const totalSamples = Math.floor(rate * durationSec);
        const preDelaySamples = Math.floor(rate * (preDelaySec || 0.025));
        const srScale = rate / 44100;

        const combLengthsL = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map(l => Math.floor(l * srScale));
        const combLengthsR = [1139, 1211, 1300, 1379, 1445, 1514, 1580, 1640].map(l => Math.floor(l * srScale));

        const allpassLengthsL = [556, 441, 341, 225].map(l => Math.floor(l * srScale));
        const allpassLengthsR = [579, 464, 364, 248].map(l => Math.floor(l * srScale));

        const feedback = Math.min(0.96, Math.max(0.70, 0.75 + roomSize * 0.20));
        const damp = Math.min(0.8, Math.max(0.1, damping));

        function processChannel(combLengths, allpassLengths) {
            const combBuffers = combLengths.map(len => new Float32Array(len));
            const combIndices = new Int32Array(combLengths.length);
            const combFilterStores = new Float32Array(combLengths.length);

            const apBuffers = allpassLengths.map(len => new Float32Array(len));
            const apIndices = new Int32Array(allpassLengths.length);
            const apGain = 0.5;

            const out = new Float32Array(totalSamples);

            for (let i = 0; i < totalSamples; i++) {
                let inputSample = (i === preDelaySamples) ? 1.0 : 0.0;

                let combSum = 0;
                for (let c = 0; c < combLengths.length; c++) {
                    const len = combLengths[c];
                    const idx = combIndices[c];
                    const buf = combBuffers[c];

                    const delayed = buf[idx];
                    combFilterStores[c] = (delayed * (1 - damp)) + (combFilterStores[c] * damp);
                    buf[idx] = inputSample + (combFilterStores[c] * feedback);

                    combIndices[c] = (idx + 1) % len;
                    combSum += delayed;
                }

                let apInput = combSum * 0.125;
                for (let a = 0; a < allpassLengths.length; a++) {
                    const len = allpassLengths[a];
                    const idx = apIndices[a];
                    const buf = apBuffers[a];

                    const delayed = buf[idx];
                    const apOut = -apGain * apInput + delayed;
                    buf[idx] = apInput + (delayed * apGain);

                    apIndices[a] = (idx + 1) % len;
                    apInput = apOut;
                }

                out[i] = apInput;
            }

            // Early reflections with Pioneer lateral stereo widening (IACC)
            const erTaps = [
                { t: 0.012, g: 0.55 },
                { t: 0.024, g: 0.45 },
                { t: 0.042, g: 0.35 },
                { t: 0.065, g: 0.25 }
            ];
            for (let j = 0; j < erTaps.length; j++) {
                const idx = Math.floor(rate * (preDelaySec + erTaps[j].t));
                if (idx < totalSamples) {
                    out[idx] += erTaps[j].g;
                }
            }

            return out;
        }

        const buf = ctx.createBuffer(2, totalSamples, rate);
        const left = processChannel(combLengthsL, allpassLengthsL);
        const right = processChannel(combLengthsR, allpassLengthsR);

        let maxAmp = 0.0001;
        for (let i = 0; i < totalSamples; i++) {
            if (Math.abs(left[i]) > maxAmp) maxAmp = Math.abs(left[i]);
            if (Math.abs(right[i]) > maxAmp) maxAmp = Math.abs(right[i]);
        }
        const norm = 0.95 / maxAmp;
        const outL = buf.getChannelData(0);
        const outR = buf.getChannelData(1);
        for (let i = 0; i < totalSamples; i++) {
            outL[i] = left[i] * norm;
            outR[i] = right[i] * norm;
        }
        return buf;
    }

    function applyAllCurrentSettings() {
        if (!audioCtx || !sourceNode) return;

        // Apply EQ Gains
        if (eqFilters.length > 0 && currentDspState.eqGains) {
            eqFilters.forEach((f, i) => {
                if (i < currentDspState.eqGains.length) {
                    f.gain.value = parseFloat(currentDspState.eqGains[i]) || 0;
                }
            });
        }
        // Apply Bass Boost
        if (bassFilter) {
            bassFilter.gain.value = parseFloat(currentDspState.bassBoost) || 0;
        }
        // Apply ASR
        if (asrFilter) {
            asrFilter.gain.value = currentDspState.asr ? 6 : 0;
        }
        // Apply Loudness
        if (loudFilter) {
            loudFilter.gain.value = currentDspState.loud ? 4 : 0;
        }
        // Apply Live Stage / SFC Mode
        if (convolver && wetGainNode && dryGainNode) {
            const mode = currentDspState.liveMode;
            if (mode === 'CONCERT_HALL' || mode === 'HALL') {
                convolver.buffer = hallBuffer;
                wetGainNode.gain.setTargetAtTime(0.60, audioCtx.currentTime, 0.03); // 60% wet lush concert hall!
                dryGainNode.gain.setTargetAtTime(0.85, audioCtx.currentTime, 0.03);
                if (bassFilter) bassFilter.gain.value = 6;
                if (asrFilter) asrFilter.gain.value = 6;
            } else if (mode === 'CLUB') {
                convolver.buffer = clubBuffer;
                wetGainNode.gain.setTargetAtTime(0.25, audioCtx.currentTime, 0.03);
                dryGainNode.gain.setTargetAtTime(1.00, audioCtx.currentTime, 0.03);
                if (bassFilter) bassFilter.gain.value = 14;
                if (asrFilter) asrFilter.gain.value = 3;
            } else if (mode === 'LIVE_STAGE') {
                convolver.buffer = stageBuffer;
                wetGainNode.gain.setTargetAtTime(0.45, audioCtx.currentTime, 0.03);
                dryGainNode.gain.setTargetAtTime(0.95, audioCtx.currentTime, 0.03);
                if (bassFilter) bassFilter.gain.value = 8;
                if (asrFilter) asrFilter.gain.value = 8;
            } else if (mode === 'STUDIO') {
                wetGainNode.gain.setTargetAtTime(0.00, audioCtx.currentTime, 0.03);
                dryGainNode.gain.setTargetAtTime(1.00, audioCtx.currentTime, 0.03);
                if (bassFilter) bassFilter.gain.value = 0;
                if (asrFilter) asrFilter.gain.value = 0;
            }
        }
        sendLog('DSP_ACTIVE: LOCKED AND RUNNING (' + currentDspState.liveMode + ')');
    }

    function hookAudio() {
        const isYouTube = window.location.hostname.includes('youtube') || window.location.hostname.includes('googlevideo');
        if (!isYouTube) return;

        const video = document.querySelector('video.video-stream, video.html5-main-video') || document.querySelector('video');
        if (!video) return;
        if (video.id === 'oel-bg-video' || video.hasAttribute('data-no-hook')) return;

        if (video === hookedVideo && sourceNode) {
            if (audioCtx && audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            return;
        }

        try {
            sendLog('Attempting hookAudio: readyState=' + video.readyState + ', paused=' + video.paused);

            if (!audioCtx) {
                audioCtx = new (window.AudioContext || window.webkitAudioContext)();
                sendLog('AudioContext created: state=' + audioCtx.state + ', sampleRate=' + audioCtx.sampleRate);
            }
            if (audioCtx.state === 'suspended') {
                audioCtx.resume();
            }

            // Pre-calculate Pioneer Schroeder impulse buffers
            if (!hallBuffer) {
                hallBuffer = buildImpulseResponse(audioCtx, 3.2, 0.92, 0.28, 0.030); // Majestic Concert Hall
                clubBuffer = buildImpulseResponse(audioCtx, 0.9, 0.45, 0.40, 0.012); // Night Club
                stageBuffer = buildImpulseResponse(audioCtx, 1.8, 0.72, 0.20, 0.035); // Live Stage
                sendLog('Impulse responses precalculated successfully!');
            }

            sourceNode = audioCtx.createMediaElementSource(video);
            hookedVideo = video;
            sendLog('SUCCESS! createMediaElementSource connected to video element!');

            // 1. Pioneer Super Todoroki Bass
            bassFilter = audioCtx.createBiquadFilter();
            bassFilter.type = 'lowshelf';
            bassFilter.frequency.value = 70;
            bassFilter.gain.value = 6;

            // 2. 7-Band Graphic Equalizer with pro-audio Q=1.1
            const freqs = [50, 125, 315, 800, 2000, 5000, 12500];
            let prev = bassFilter;
            eqFilters = freqs.map((f, i) => {
                const filt = audioCtx.createBiquadFilter();
                filt.type = (i === 0) ? 'lowshelf' : ((i === freqs.length - 1) ? 'highshelf' : 'peaking');
                filt.frequency.value = f;
                filt.Q.value = 1.1;
                filt.gain.value = (i === 0) ? 8 : ((i === 1) ? 5 : ((i === 4) ? 4 : ((i === 5) ? 6 : ((i === 6) ? 7 : 0))));
                prev.connect(filt);
                prev = filt;
                return filt;
            });

            // 3. ASR harmonic excitation
            asrFilter = audioCtx.createBiquadFilter();
            asrFilter.type = 'peaking';
            asrFilter.frequency.value = 10000;
            asrFilter.Q.value = 1.5;
            asrFilter.gain.value = 5;
            prev.connect(asrFilter);
            prev = asrFilter;

            // 4. Loudness filter
            loudFilter = audioCtx.createBiquadFilter();
            loudFilter.type = 'lowshelf';
            loudFilter.frequency.value = 100;
            loudFilter.gain.value = 4;
            prev.connect(loudFilter);
            prev = loudFilter;

            // 5. Pioneer SFC Convolution Reverb Engine (Parallel Send)
            convolver = audioCtx.createConvolver();
            convolver.buffer = hallBuffer;

            wetGainNode = audioCtx.createGain();
            wetGainNode.gain.value = 0.60; // Lush concert hall parallel wet

            dryGainNode = audioCtx.createGain();
            dryGainNode.gain.value = 0.85; // Direct punch

            prev.connect(dryGainNode);
            prev.connect(convolver);
            convolver.connect(wetGainNode);

            // 6. Summing Mixer
            const mixerNode = audioCtx.createGain();
            mixerNode.gain.value = 1.0;
            dryGainNode.connect(mixerNode);
            wetGainNode.connect(mixerNode);

            // 7. Master Gain & Limiter
            const masterGain = audioCtx.createGain();
            masterGain.gain.value = 0.85;

            const limiter = audioCtx.createDynamicsCompressor();
            limiter.threshold.value = -0.5;
            limiter.knee.value = 0;
            limiter.ratio.value = 20;
            limiter.attack.value = 0.003;
            limiter.release.value = 0.050;

            mixerNode.connect(masterGain);
            masterGain.connect(limiter);
            limiter.connect(audioCtx.destination);

            sourceNode.connect(bassFilter);

            // Attach auto-resume triggers to the video itself
            ['play', 'playing', 'timeupdate'].forEach(evt => {
                video.addEventListener(evt, () => {
                    if (audioCtx && audioCtx.state === 'suspended') {
                        audioCtx.resume();
                    }
                }, { passive: true });
            });

            // Immediately apply active settings
            applyAllCurrentSettings();
            console.log('[Carrozzeria DSP] Full audio graph hooked and active!');
        } catch(e) {
            sendLog('HOOK_AUDIO_ERROR: ' + (e.stack || e.message || e));
            console.error('[Carrozzeria DSP] hookAudio error:', e);
        }
    }

    // Auto-resume on user interaction
    ['click', 'keydown', 'pointerdown', 'touchstart', 'play', 'playing'].forEach(evt => {
        document.addEventListener(evt, () => {
            hookAudio();
            if (audioCtx && audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
        }, { passive: true });
    });

    // Master DSP application function
    window.applyDsp = function(msg) {
        if (typeof msg === 'string') {
            try { msg = JSON.parse(msg); } catch(e) {}
        }
        if (!msg || typeof msg !== 'object') return;

        hookAudio();
        if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume();
        }

        if (msg.action === 'SET_EQ_BAND') {
            const idx = parseInt(msg.index);
            const val = parseFloat(msg.gain) || 0;
            if (!currentDspState.eqGains) currentDspState.eqGains = [0,0,0,0,0,0,0];
            currentDspState.eqGains[idx] = val;
            if (eqFilters[idx]) eqFilters[idx].gain.value = val;
            console.log('[Carrozzeria DSP] Band', idx, 'set to', val, 'dB');
        } else if (msg.action === 'SET_EQ_PRESET') {
            currentDspState.presetName = msg.presetName;
            currentDspState.eqGains = msg.gains || [0,0,0,0,0,0,0];
            if (msg.bassBoost !== undefined) currentDspState.bassBoost = parseFloat(msg.bassBoost) || 0;
            if (eqFilters.length > 0) {
                eqFilters.forEach((f, i) => {
                    if (i < currentDspState.eqGains.length) f.gain.value = parseFloat(currentDspState.eqGains[i]) || 0;
                });
            }
            if (bassFilter) bassFilter.gain.value = currentDspState.bassBoost;
            console.log('[Carrozzeria DSP] Preset applied:', msg.presetName, currentDspState.eqGains);
        } else if (msg.action === 'SET_ASR') {
            currentDspState.asr = !!msg.enabled;
            if (asrFilter) asrFilter.gain.value = currentDspState.asr ? 6 : 0;
            console.log('[Carrozzeria DSP] ASR:', currentDspState.asr);
        } else if (msg.action === 'SET_LOUD') {
            currentDspState.loud = !!msg.enabled;
            if (loudFilter) loudFilter.gain.value = currentDspState.loud ? 4 : 0;
            console.log('[Carrozzeria DSP] Loudness:', currentDspState.loud);
        } else if (msg.action === 'SET_LIVE_STAGE') {
            currentDspState.liveMode = msg.mode;
            const mode = msg.mode;
            if (convolver && wetGainNode && dryGainNode) {
                if (mode === 'CONCERT_HALL' || mode === 'HALL') {
                    // Majestic Concert Hall: 60% wet, 85% dry
                    convolver.buffer = hallBuffer;
                    wetGainNode.gain.setTargetAtTime(0.60, audioCtx.currentTime, 0.03);
                    dryGainNode.gain.setTargetAtTime(0.85, audioCtx.currentTime, 0.03);
                    if (bassFilter) bassFilter.gain.value = 6;
                    if (asrFilter) asrFilter.gain.value = 6;
                } else if (mode === 'CLUB') {
                    // Night Club: Todoroki bass +14dB
                    convolver.buffer = clubBuffer;
                    wetGainNode.gain.setTargetAtTime(0.25, audioCtx.currentTime, 0.03);
                    dryGainNode.gain.setTargetAtTime(1.00, audioCtx.currentTime, 0.03);
                    if (bassFilter) bassFilter.gain.value = 14;
                    if (asrFilter) asrFilter.gain.value = 3;
                } else if (mode === 'LIVE_STAGE') {
                    // Live Stage: 45% wet
                    convolver.buffer = stageBuffer;
                    wetGainNode.gain.setTargetAtTime(0.45, audioCtx.currentTime, 0.03);
                    dryGainNode.gain.setTargetAtTime(0.95, audioCtx.currentTime, 0.03);
                    if (bassFilter) bassFilter.gain.value = 8;
                    if (asrFilter) asrFilter.gain.value = 8;
                } else if (mode === 'STUDIO') {
                    // Studio Direct: 0% wet flat
                    wetGainNode.gain.setTargetAtTime(0.00, audioCtx.currentTime, 0.03);
                    dryGainNode.gain.setTargetAtTime(1.00, audioCtx.currentTime, 0.03);
                    if (bassFilter) bassFilter.gain.value = 0;
                    if (asrFilter) asrFilter.gain.value = 0;
                }
            }
            console.log('[Carrozzeria DSP] SFC Live Mode set to:', mode);
        } else if (msg.action === 'SET_VOLUME') {
            const video = document.querySelector('video');
            if (video && typeof msg.volume === 'number') {
                video.volume = Math.max(0, Math.min(1, msg.volume / 100));
            }
        } else if (msg.action === 'SEEK' && typeof msg.seconds === 'number') {
            const video = document.querySelector('video');
            if (video) {
                video.currentTime = msg.seconds;
                console.log('[Carrozzeria DSP] Video seeked to:', msg.seconds);
            }
        }
    };

    window.addEventListener('message', (event) => {
        window.applyDsp(event.data);
    });

    // Real-time synchronization (ONLY for YouTube player video, NEVER for local UI / 1.mp4)
    setInterval(() => {
        const isYouTube = window.location.hostname.includes('youtube') || window.location.hostname.includes('googlevideo');
        if (!isYouTube) return;

        const video = document.querySelector('video.video-stream, video.html5-main-video') || document.querySelector('video');
        if (!video || video.id === 'oel-bg-video' || video.hasAttribute('data-no-hook')) return;
        if (typeof video.currentTime !== 'number' || isNaN(video.currentTime)) return;
        if (typeof video.duration !== 'number' || isNaN(video.duration) || video.duration <= 20) return;

        try {
            window.parent.postMessage({
                action: 'YT_TIME_UPDATE',
                currentTime: video.currentTime,
                duration: video.duration,
                paused: video.paused
            }, '*');
        } catch(e) {}
    }, 250);

    // Track finish auto-advance (ONLY for YouTube player video)
    document.addEventListener('ended', (e) => {
        const isYouTube = window.location.hostname.includes('youtube') || window.location.hostname.includes('googlevideo');
        if (!isYouTube) return;
        if (e.target && (e.target.id === 'oel-bg-video' || e.target.hasAttribute('data-no-hook'))) return;

        try {
            window.parent.postMessage({ action: 'YT_ENDED' }, '*');
        } catch(e) {}
    }, true);

    setInterval(hookAudio, 400);
})();
");

                webView.CoreWebView2.Navigate("https://appassets.dirotube.com/index.html");
            }
            catch (Exception ex)
            {
                MessageBox.Show($"WebView2 xatolik: {ex.Message}", "Diro Tube", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private static void LogDebug(string text)
        {
            try
            {
                string logFile = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "dsp_debug.log");
                File.AppendAllText(logFile, $"[{DateTime.Now:HH:mm:ss.fff}] {text}\r\n");
            }
            catch { }
        }

        private async void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                string rawJson = e.WebMessageAsJson;
                using var doc = JsonDocument.Parse(rawJson);
                var root = doc.RootElement;

                if (root.TryGetProperty("action", out var actionProp))
                {
                    string action = actionProp.GetString() ?? "";
                    if (action == "IFRAME_LOG" && root.TryGetProperty("text", out var textProp))
                    {
                        LogDebug($"[JS] {textProp.GetString()}");
                    }
                    else if (action == "search" && root.TryGetProperty("query", out var queryProp))
                    {
                        string query = queryProp.GetString() ?? "";
                        LogDebug($"Search requested: {query}");
                        await PerformYouTubeSearchAsync(query);
                    }
                    else if (action.StartsWith("SET_") || action == "SEEK")
                    {
                        LogDebug($"Broadcasting {action} to {activeFrames.Count} active frames and main window: {rawJson}");
                        string jsCode = $"if (window.applyDsp) window.applyDsp({rawJson}); else window.postMessage({rawJson}, '*');";
                        try { await webView.CoreWebView2.ExecuteScriptAsync(jsCode); } catch { }
                        foreach (var frame in activeFrames.ToArray())
                        {
                            try { await frame.ExecuteScriptAsync(jsCode); } catch { }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                LogDebug("WebMessage error: " + ex.Message);
            }
        }

        private async Task PerformYouTubeSearchAsync(string query)
        {
            try
            {
                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(8));
                string encoded = Uri.EscapeDataString(query);
                string url = $"https://www.youtube.com/results?search_query={encoded}";
                var response = await httpClient.GetAsync(url, cts.Token);
                string html = await response.Content.ReadAsStringAsync();

                var tracks = ParseYouTubeHtml(html);
                LogDebug($"Search completed: found {tracks.Count} tracks for '{query}'");

                var responseObj = new
                {
                    action = "searchResults",
                    query = query,
                    tracks = tracks
                };

                string jsonResponse = JsonSerializer.Serialize(responseObj);
                await Dispatcher.InvokeAsync(() =>
                {
                    webView.CoreWebView2.PostWebMessageAsJson(jsonResponse);
                });
            }
            catch (Exception ex)
            {
                LogDebug("Search error: " + ex.Message);
            }
        }

        private List<object> ParseYouTubeHtml(string html)
        {
            var list = new List<object>();
            var seenIds = new HashSet<string>();

            string[] chunks = html.Split(new[] { "\"videoRenderer\":{\"videoId\":\"", "\"compactVideoRenderer\":{\"videoId\":\"" }, StringSplitOptions.RemoveEmptyEntries);

            for (int i = 1; i < chunks.Length && list.Count < 30; i++)
            {
                string c = chunks[i];
                if (c.Length < 11) continue;
                string videoId = c.Substring(0, 11);
                if (videoId.Contains("\"") || videoId.Contains("\\") || !seenIds.Add(videoId)) continue;

                string title = "Musiqa";
                var titleMatch = Regex.Match(c, "\"title\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"\\}");
                if (!titleMatch.Success) titleMatch = Regex.Match(c, "\"title\":\\{\"simpleText\":\"([^\"]+)\"\\}");
                if (!titleMatch.Success) titleMatch = Regex.Match(c, "\"title\":\\{\"accessibility\":\\{\"accessibilityData\":\\{\"label\":\"([^\"]+)\"\\}");
                if (titleMatch.Success) title = Regex.Unescape(titleMatch.Groups[1].Value);

                string artist = "YouTube Artist";
                var artistMatch = Regex.Match(c, "BylineText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"\\}");
                if (!artistMatch.Success) artistMatch = Regex.Match(c, "ownerText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"\\}");
                if (!artistMatch.Success) artistMatch = Regex.Match(c, "shortBylineText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"\\}");
                if (artistMatch.Success) artist = Regex.Unescape(artistMatch.Groups[1].Value);

                string duration = "03:45";
                var durMatch = Regex.Match(c, "\"lengthText\":\\{\"simpleText\":\"([^\"]+)\"\\}");
                if (!durMatch.Success) durMatch = Regex.Match(c, "\"lengthText\":\\{\"accessibility\":\\{\"accessibilityData\":\\{\"label\":\"([^\"]+)\"\\}");
                if (durMatch.Success) duration = durMatch.Groups[1].Value;

                string views = "Ko'rilgan";
                var viewsMatch = Regex.Match(c, "\"viewCountText\":\\{\"simpleText\":\"([^\"]+)\"\\}");
                if (!viewsMatch.Success) viewsMatch = Regex.Match(c, "\"shortViewCountText\":\\{\"simpleText\":\"([^\"]+)\"\\}");
                if (!viewsMatch.Success) viewsMatch = Regex.Match(c, "\"shortViewCountText\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\"\\}");
                if (viewsMatch.Success) views = viewsMatch.Groups[1].Value.Replace(" views", "").Replace(" marta", "");

                string thumb = $"https://img.youtube.com/vi/{videoId}/hqdefault.jpg";

                list.Add(new
                {
                    id = videoId,
                    title = title,
                    artist = artist,
                    duration = duration,
                    views = views,
                    thumb = thumb
                });
            }

            return list;
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        }

        private void BtnMinimize_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void BtnMaximize_Click(object sender, RoutedEventArgs e)
        {
            WindowState = (WindowState == WindowState.Maximized) ? WindowState.Normal : WindowState.Maximized;
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
    }
}