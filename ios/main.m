#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

static int local_port = 18080;

void startLocalServer() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) return;

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = inet_addr("127.0.0.1");
        address.sin_port = htons(local_port);

        if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
            close(server_fd);
            return;
        }

        if (listen(server_fd, 20) < 0) {
            close(server_fd);
            return;
        }

        NSLog(@"[DiroTube LocalServer] Listening on http://127.0.0.1:%d", local_port);

        NSString *playerPath = [[NSBundle mainBundle] pathForResource:@"player" ofType:@"html"];
        NSData *playerData = [NSData dataWithContentsOfFile:playerPath];
        if (!playerData) {
            NSString *defaultPlayer = @"<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'><meta name='referrer' content='strict-origin-when-cross-origin'><style>*{margin:0;padding:0;box-sizing:border-box;}html,body{width:100%;height:100%;background:#000;overflow:hidden;}iframe{width:100%;height:100%;border:none;display:block;}</style></head><body><iframe id='p' allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture' allowfullscreen playsinline webkit-playsinline referrerpolicy='strict-origin-when-cross-origin'></iframe><script>const p=new URLSearchParams(window.location.search);const v=p.get('v')||'YzQknv9Z9y8';const f=document.getElementById('p');f.src='https://www.youtube-nocookie.com/embed/'+v+'?autoplay=1&playsinline=1&enablejsapi=1&rel=0';window.addEventListener('message',e=>{if(e.data){if(f&&f.contentWindow&&e.source!==f.contentWindow){try{f.contentWindow.postMessage(e.data,'*');}catch(err){}}if(e.source===f.contentWindow&&window.parent&&window.parent!==window){try{window.parent.postMessage(e.data,'*');}catch(err){}}}});</script></body></html>";
            playerData = [defaultPlayer dataUsingEncoding:NSUTF8StringEncoding];
        }

        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;

            char buffer[2048] = {0};
            read(client_fd, buffer, sizeof(buffer) - 1);

            NSString *header = [NSString stringWithFormat:
                @"HTTP/1.1 200 OK\r\n"
                @"Content-Type: text/html; charset=utf-8\r\n"
                @"Content-Length: %lu\r\n"
                @"Access-Control-Allow-Origin: *\r\n"
                @"Connection: close\r\n\r\n", (unsigned long)playerData.length];

            NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
            write(client_fd, headerData.bytes, headerData.length);
            write(client_fd, playerData.bytes, playerData.length);
            close(client_fd);
        }
    });
}

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Start Local HTTP Server for error-free YouTube player bridging (No 404, No Error 153)
    startLocalServer();

    // 2. Enable Non-stop Background Audio Playback
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback
                        mode:AVAudioSessionModeMoviePlayback
                     options:0
                       error:nil];
        [session setActive:YES error:nil];
    } @catch (NSException *e) {
        NSLog(@"AudioSession setup error: %@", e);
    }

    // 3. Full-screen window
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];

    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];

    // 4. Configure WKWebView for Inline Media, Background Playback, & Script Bridging
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    config.allowsAirPlayForMediaPlayback = YES;
    config.allowsPictureInPictureMediaPlayback = YES;

    // Preferences
    WKPreferences *prefs = config.preferences;
    prefs.javaScriptCanOpenWindowsAutomatically = YES;
    @try {
        [prefs setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
        [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
    } @catch (NSException *e) {
        NSLog(@"Preferences error: %@", e);
    }

    // Web Audio Carrozzeria DSP Engine Injected into all subframes (including YouTube)
    NSString *dspScript = @"\
(function() {\
    var ctx = null;\
    var eqFilters = [];\
    var delayNode = null;\
    var feedbackNode = null;\
    var wetGain = null;\
    var dryGain = null;\
    var bassNode = null;\
    var isHooked = false;\
    function initDsp(v) {\
        if (isHooked || !v) return;\
        try {\
            var AudioContext = window.AudioContext || window.webkitAudioContext;\
            if (!AudioContext) return;\
            ctx = new AudioContext();\
            var source = ctx.createMediaElementSource(v);\
            var freqs = [63, 160, 400, 1000, 2500, 6300, 16000];\
            eqFilters = freqs.map(function(f, i) {\
                var filter = ctx.createBiquadFilter();\
                if (i === 0) filter.type = 'lowshelf';\
                else if (i === freqs.length - 1) filter.type = 'highshelf';\
                else filter.type = 'peaking';\
                filter.frequency.value = f;\
                filter.gain.value = 0;\
                return filter;\
            });\
            source.connect(eqFilters[0]);\
            for (var i = 0; i < eqFilters.length - 1; i++) {\
                eqFilters[i].connect(eqFilters[i+1]);\
            }\
            var lastEq = eqFilters[eqFilters.length - 1];\
            bassNode = ctx.createBiquadFilter();\
            bassNode.type = 'lowshelf';\
            bassNode.frequency.value = 100;\
            bassNode.gain.value = 12;\
            lastEq.connect(bassNode);\
            delayNode = ctx.createDelay();\
            delayNode.delayTime.value = 0.08;\
            feedbackNode = ctx.createGain();\
            feedbackNode.gain.value = 0.55;\
            var lp = ctx.createBiquadFilter();\
            lp.type = 'lowpass';\
            lp.frequency.value = 2800;\
            wetGain = ctx.createGain();\
            wetGain.gain.value = 0.65;\
            dryGain = ctx.createGain();\
            dryGain.gain.value = 1.0;\
            bassNode.connect(dryGain);\
            dryGain.connect(ctx.destination);\
            bassNode.connect(delayNode);\
            delayNode.connect(lp);\
            lp.connect(feedbackNode);\
            feedbackNode.connect(delayNode);\
            lp.connect(wetGain);\
            wetGain.connect(ctx.destination);\
            isHooked = true;\
            console.log('[DiroTube Native DSP] Audio graph hooked successfully!');\
        } catch(err) {\
            console.log('[DiroTube Native DSP Hook Safe Catch]: ' + err);\
        }\
    }\
    function lookForVideo() {\
        var v = document.querySelector('video');\
        if (v) {\
            initDsp(v);\
        } else {\
            setTimeout(lookForVideo, 500);\
        }\
    }\
    document.addEventListener('DOMContentLoaded', lookForVideo);\
    lookForVideo();\
    window.addEventListener('message', function(e) {\
        if (!e.data) return;\
        var d = e.data;\
        if (typeof d === 'string') {\
            try { d = JSON.parse(d); } catch(ex) { return; }\
        }\
        if (ctx && ctx.state === 'suspended') { ctx.resume(); }\
        if (d.type === 'SET_EQ' && Array.isArray(d.gains) && eqFilters.length > 0) {\
            d.gains.forEach(function(g, idx) {\
                if (eqFilters[idx]) eqFilters[idx].gain.setTargetAtTime(g, ctx.currentTime, 0.05);\
            });\
        }\
        if (d.type === 'SET_DSP' && delayNode && wetGain) {\
            if (d.mode === 'HALL') {\
                wetGain.gain.setTargetAtTime(0.70, ctx.currentTime, 0.05);\
                delayNode.delayTime.setTargetAtTime(0.08, ctx.currentTime, 0.05);\
                feedbackNode.gain.setTargetAtTime(0.60, ctx.currentTime, 0.05);\
            } else if (d.mode === 'STAGE') {\
                wetGain.gain.setTargetAtTime(0.45, ctx.currentTime, 0.05);\
                delayNode.delayTime.setTargetAtTime(0.04, ctx.currentTime, 0.05);\
                feedbackNode.gain.setTargetAtTime(0.40, ctx.currentTime, 0.05);\
            } else if (d.mode === 'CLUB') {\
                wetGain.gain.setTargetAtTime(0.20, ctx.currentTime, 0.05);\
                if (bassNode) bassNode.gain.setTargetAtTime(16, ctx.currentTime, 0.05);\
            } else if (d.mode === 'STUDIO') {\
                wetGain.gain.setTargetAtTime(0.0, ctx.currentTime, 0.05);\
                feedbackNode.gain.setTargetAtTime(0.0, ctx.currentTime, 0.05);\
            }\
        }\
        if (d.type === 'SET_BASS' && bassNode) {\
            bassNode.gain.setTargetAtTime(d.value, ctx.currentTime, 0.05);\
        }\
    });\
})();";

    // Script message handler for YouTube Search & DSP
    WKUserContentController *contentController = [[WKUserContentController alloc] init];
    [contentController addScriptMessageHandler:self name:@"diroTube"];
    WKUserScript *dspUserScript = [[WKUserScript alloc] initWithSource:dspScript
                                                        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                     forMainFrameOnly:NO];
    [contentController addUserScript:dspUserScript];
    config.userContentController = contentController;

    // Viewport-fit full screen web view
    self.webView = [[WKWebView alloc] initWithFrame:viewController.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.opaque = YES;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.scrollEnabled = NO; // Tab content handles inner scrolling
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
    self.webView.navigationDelegate = self;

    // 5. Load index.html from bundle
    NSString *indexPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (indexPath) {
        NSURL *url = [NSURL fileURLWithPath:indexPath];
        [self.webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    }

    [viewController.view addSubview:self.webView];
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];

    return YES;
}

#pragma mark - String Cleaning Helper

static NSString *cleanText(NSString *raw) {
    if (!raw) return @"";
    NSMutableString *s = [raw mutableCopy];
    [s replaceOccurrencesOfString:@"\\\"" withString:@"\"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\\\\" withString:@"\\" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&#39;" withString:@"'" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&lt;" withString:@"<" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&gt;" withString:@">" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\\u0026" withString:@"&" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\\u0027" withString:@"'" options:0 range:NSMakeRange(0, s.length)];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *action = body[@"action"];

    if ([action isEqualToString:@"search"]) {
        NSString *query = body[@"query"];
        if (query && query.length > 0) {
            [self performYouTubeSearch:query];
        }
    }
}

#pragma mark - Native YouTube Search

- (void)performYouTubeSearch:(NSString *)query {
    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://www.youtube.com/results?search_query=%@", encoded];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    // Use Desktop Chrome User-Agent to guarantee full desktop JSON/HTML payload with 25+ real results
    [request setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[Native Search Error]: %@", error ? error.localizedDescription : @"No data");
            return;
        }

        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) {
            html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        if (!html) return;

        NSArray *tracks = [self parseYouTubeHtml:html query:query];
        NSDictionary *respObj = @{
            @"action": @"searchResults",
            @"query": query,
            @"tracks": tracks
        };

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:respObj options:0 error:nil];
        if (!jsonData) return;
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *js = [NSString stringWithFormat:@"if (window.onNativeSearchResults) window.onNativeSearchResults(%@);", jsonString];
            [self.webView evaluateJavaScript:js completionHandler:nil];
        });
    }] resume];
}

- (NSArray *)parseYouTubeHtml:(NSString *)html query:(NSString *)query {
    NSMutableArray *list = [NSMutableArray array];
    NSMutableSet *seenIds = [NSMutableSet set];

    // Search for videoRenderer and compactVideoRenderer chunks
    NSArray *chunks = [html componentsSeparatedByString:@"\"videoRenderer\":{\"videoId\":\""];
    if (chunks.count <= 1) {
        chunks = [html componentsSeparatedByString:@"\"compactVideoRenderer\":{\"videoId\":\""];
    }

    for (NSUInteger i = 1; i < chunks.count && list.count < 30; i++) {
        NSString *c = chunks[i];
        if (c.length < 11) continue;
        NSString *videoId = [c substringToIndex:11];
        if ([videoId containsString:@"\""] || [videoId containsString:@"\\"] || [seenIds containsObject:videoId]) {
            continue;
        }
        [seenIds addObject:videoId];

        // Title extraction
        NSString *title = query;
        NSRange titleRange = [c rangeOfString:@"\"title\":{\"runs\":[{\"text\":\""];
        if (titleRange.location != NSNotFound) {
            NSUInteger start = titleRange.location + titleRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                title = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        } else {
            NSRange accRange = [c rangeOfString:@"\"title\":{\"accessibility\":{\"accessibilityData\":{\"label\":\""];
            if (accRange.location != NSNotFound) {
                NSUInteger start = accRange.location + accRange.length;
                NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
                if (endQuote.location != NSNotFound) {
                    title = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
                }
            }
        }
        title = cleanText(title);

        // Artist / Channel extraction
        NSString *artist = @"YouTube";
        NSRange bylineRange = [c rangeOfString:@"\"longBylineText\":{\"runs\":[{\"text\":\""];
        if (bylineRange.location != NSNotFound) {
            NSUInteger start = bylineRange.location + bylineRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                artist = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        } else {
            NSRange ownerRange = [c rangeOfString:@"\"ownerText\":{\"runs\":[{\"text\":\""];
            if (ownerRange.location != NSNotFound) {
                NSUInteger start = ownerRange.location + ownerRange.length;
                NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
                if (endQuote.location != NSNotFound) {
                    artist = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
                }
            }
        }
        artist = cleanText(artist);

        // Duration extraction
        NSString *duration = @"03:30";
        NSRange lengthRange = [c rangeOfString:@"\"lengthText\":{\"simpleText\":\""];
        if (lengthRange.location != NSNotFound) {
            NSUInteger start = lengthRange.location + lengthRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                duration = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        }
        duration = cleanText(duration);

        // Views extraction
        NSString *views = @"1M ko'rildi";
        NSRange viewRange = [c rangeOfString:@"\"viewCountText\":{\"simpleText\":\""];
        if (viewRange.location != NSNotFound) {
            NSUInteger start = viewRange.location + viewRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                views = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        } else {
            NSRange shortViewRange = [c rangeOfString:@"\"shortViewCountText\":{\"simpleText\":\""];
            if (shortViewRange.location != NSNotFound) {
                NSUInteger start = shortViewRange.location + shortViewRange.length;
                NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
                if (endQuote.location != NSNotFound) {
                    views = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
                }
            }
        }
        views = cleanText(views);

        NSString *thumb = [NSString stringWithFormat:@"https://img.youtube.com/vi/%@/hqdefault.jpg", videoId];

        [list addObject:@{
            @"id": videoId,
            @"title": title,
            @"artist": artist,
            @"duration": duration,
            @"views": views,
            @"thumb": thumb
        }];
    }

    return list;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
