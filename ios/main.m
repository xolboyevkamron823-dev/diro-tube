#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Enable Background Audio for Non-stop YouTube & Dolphin Music playback
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     mode:AVAudioSessionModeDefault
                                  options:AVAudioSessionCategoryOptionMixWithOthers
                                    error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    // 2. Setup Full-screen iOS Window
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];

    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor blackColor];

    // 3. Configure WKWebView with inline media playback & background audio
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:viewController.view.bounds configuration:config];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.backgroundColor = [UIColor blackColor];
    webView.scrollView.bounces = NO;

    // 4. Load Carrozzeria YouTube Player Web Engine
    NSString *indexPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (indexPath) {
        NSURL *url = [NSURL fileURLWithPath:indexPath];
        [webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    }

    [viewController.view addSubview:webView];
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];

    return YES;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
