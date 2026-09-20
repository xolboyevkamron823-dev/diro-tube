#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Enable Non-stop Background Audio Playback
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

    // 2. Full-screen window
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];

    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];

    // 3. Configure WKWebView for Inline Media, Background Playback, & Script Bridging
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

    // Script message handler for YouTube Search & DSP
    WKUserContentController *contentController = [[WKUserContentController alloc] init];
    [contentController addScriptMessageHandler:self name:@"diroTube"];
    config.userContentController = contentController;

    // Viewport-fit full screen web view
    self.webView = [[WKWebView alloc] initWithFrame:viewController.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.opaque = YES;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.scrollEnabled = NO; // Tab content handles inner scrolling
    self.webView.navigationDelegate = self;

    // 4. Load index.html from bundle
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
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 8.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[Native Search Error]: %@", error ? error.localizedDescription : @"No data");
            return;
        }

        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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

    NSArray *chunks = [html componentsSeparatedByString:@"\"videoRenderer\":{\"videoId\":\""];
    for (NSUInteger i = 1; i < chunks.count && list.count < 30; i++) {
        NSString *c = chunks[i];
        if (c.length < 11) continue;
        NSString *videoId = [c substringToIndex:11];
        if ([videoId containsString:@"\""] || [videoId containsString:@"\\"] || [seenIds containsObject:videoId]) {
            continue;
        }
        [seenIds addObject:videoId];

        // Title
        NSString *title = query;
        NSRange titleRange = [c rangeOfString:@"\"title\":{\"runs\":[{\"text\":\""];
        if (titleRange.location != NSNotFound) {
            NSUInteger start = titleRange.location + titleRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                title = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        }

        // Artist / Channel
        NSString *artist = @"YouTube";
        NSRange ownerRange = [c rangeOfString:@"\"ownerText\":{\"runs\":[{\"text\":\""];
        if (ownerRange.location != NSNotFound) {
            NSUInteger start = ownerRange.location + ownerRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                artist = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        }

        // Duration
        NSString *duration = @"03:30";
        NSRange lengthRange = [c rangeOfString:@"\"lengthText\":{\"simpleText\":\""];
        if (lengthRange.location != NSNotFound) {
            NSUInteger start = lengthRange.location + lengthRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                duration = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        }

        // Views
        NSString *views = @"1M ko'rildi";
        NSRange viewRange = [c rangeOfString:@"\"viewCountText\":{\"simpleText\":\""];
        if (viewRange.location != NSNotFound) {
            NSUInteger start = viewRange.location + viewRange.length;
            NSRange endQuote = [c rangeOfString:@"\"" options:0 range:NSMakeRange(start, c.length - start)];
            if (endQuote.location != NSNotFound) {
                views = [c substringWithRange:NSMakeRange(start, endQuote.location - start)];
            }
        }

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
