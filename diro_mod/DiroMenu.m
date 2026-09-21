#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// Forward full interfaces
@interface DiroFloatingButton : UIView
@end

@interface DiroMenuModal : UIView
- (void)toggleVisibility;
- (void)showToast:(NSString *)message;
- (void)refreshCheatsList;
@end

@interface DiroWindow : UIWindow
@end

@interface DiroRootViewController : UIViewController
@end

static DiroWindow *g_diroWindow = nil;
static DiroFloatingButton *g_floatingButton = nil;
static DiroMenuModal *g_menuModal = nil;

// Safe native cheat caller using ASLR slide
static intptr_t get_gtasa_slide(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "gtasa")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return _dyld_get_image_vmaddr_slide(0);
}

static void trigger_native_cheat(uintptr_t offset) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + offset;
    void (*fn)(void) = (void(*)(void))addr;
    if (fn) {
        fn();
    }
}

// -----------------------------------------------------------------------------
// DiroWindow: Transparent overlay window that passes touches through to the game
// -----------------------------------------------------------------------------
@implementation DiroWindow
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.windowLevel = UIWindowLevelStatusBar + 100.0;
        self.userInteractionEnabled = YES;
    }
    return self;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene API_AVAILABLE(ios(13.0)) {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.windowLevel = UIWindowLevelStatusBar + 100.0;
        self.userInteractionEnabled = YES;
    }
    return self;
}
#endif

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil; // Pass touches through to GTA SA game!
    }
    return hitView;
}
@end

// -----------------------------------------------------------------------------
// DiroRootViewController: Handles landscape orientation and responsive layout
// -----------------------------------------------------------------------------
@implementation DiroRootViewController
- (BOOL)shouldAutorotate {
    return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        if (g_floatingButton) {
            CGRect f = g_floatingButton.frame;
            CGFloat minMargin = 12.0;
            CGFloat targetX = (f.origin.x > size.width / 2.0) ? (size.width - f.size.width - minMargin) : minMargin;
            CGFloat targetY = MIN(MAX(f.origin.y, 20.0), size.height - f.size.height - 20.0);
            g_floatingButton.frame = CGRectMake(targetX, targetY, f.size.width, f.size.height);
        }
        if (g_menuModal) {
            CGFloat mw = MIN(380.0, size.width - 24.0);
            CGFloat mh = MIN(290.0, size.height - 24.0);
            g_menuModal.frame = CGRectMake((size.width - mw) / 2.0, (size.height - mh) / 2.0, mw, mh);
        }
    } completion:nil];
}
@end

// -----------------------------------------------------------------------------
// DiroFloatingButton: Movable circular button with snap-to-edge animation
// -----------------------------------------------------------------------------
@implementation DiroFloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.95];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0].CGColor; // Gold
        self.layer.borderWidth = 2.5;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.85;
        self.layer.shadowRadius = 8.0;
        self.clipsToBounds = NO;
        self.userInteractionEnabled = YES;

        UILabel *crown = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, frame.size.width, 20)];
        crown.text = @"👑";
        crown.textAlignment = NSTextAlignmentCenter;
        crown.font = [UIFont systemFontOfSize:16];
        crown.userInteractionEnabled = NO;
        [self addSubview:crown];

        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(0, 26, frame.size.width, 16)];
        name.text = @"DIRO";
        name.textAlignment = NSTextAlignmentCenter;
        name.font = [UIFont boldSystemFontOfSize:11];
        name.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        name.userInteractionEnabled = NO;
        [self addSubview:name];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (g_menuModal) {
        [g_menuModal toggleVisibility];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);

    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    CGFloat minX = halfW + 8.0;
    CGFloat maxX = superview.bounds.size.width - halfW - 8.0;
    CGFloat minY = halfH + 12.0;
    CGFloat maxY = superview.bounds.size.height - halfH - 12.0;

    newCenter.x = MIN(MAX(newCenter.x, minX), maxX);
    newCenter.y = MIN(MAX(newCenter.y, minY), maxY);
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:superview];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat targetX = (self.center.x > superview.bounds.size.width / 2.0) ? maxX : minX;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.center = CGPointMake(targetX, self.center.y);
        } completion:nil];
    }
}
@end

// -----------------------------------------------------------------------------
// DiroMenuModal: Sleek dark acrylic cheat hub with categories and instant cheats
// -----------------------------------------------------------------------------
@interface DiroMenuModal ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subTitleLabel;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSTimer *toastTimer;
@end

@implementation DiroMenuModal

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:0.96];
        self.layer.cornerRadius = 18.0;
        self.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0].CGColor;
        self.layer.borderWidth = 1.8;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 8);
        self.layer.shadowOpacity = 0.85;
        self.layer.shadowRadius = 24.0;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = YES;

        CGFloat w = frame.size.width;
        CGFloat h = frame.size.height;

        // Title
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, w - 60, 20)];
        self.titleLabel.text = @"👑 DIRO MOD MENU";
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        self.titleLabel.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [self addSubview:self.titleLabel];

        // Subtitle
        self.subTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, w - 60, 14)];
        self.subTitleLabel.text = @"100% Offline • Ro'yxatdan o'tish shart emas";
        self.subTitleLabel.font = [UIFont systemFontOfSize:10];
        self.subTitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        [self addSubview:self.subTitleLabel];

        // Close Button
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(w - 38, 10, 28, 28);
        closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        closeBtn.layer.cornerRadius = 14;
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [closeBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        // Toast Label
        self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 46, w - 28, 18)];
        self.toastLabel.textAlignment = NSTextAlignmentCenter;
        self.toastLabel.font = [UIFont boldSystemFontOfSize:11];
        self.toastLabel.textColor = [UIColor colorWithRed:0.20 green:0.95 blue:0.45 alpha:1.0];
        self.toastLabel.alpha = 0.0;
        [self addSubview:self.toastLabel];

        // Segmented Control
        NSArray *categories = @[@"⚡ Asosiy", @"🔫 Qurollar", @"⭐ Politsiya", @"🚗 Mashinalar"];
        self.segmentedControl = [[UISegmentedControl alloc] initWithItems:categories];
        self.segmentedControl.frame = CGRectMake(14, 68, w - 28, 28);
        self.segmentedControl.selectedSegmentIndex = 0;
        if (@available(iOS 13.0, *)) {
            self.segmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.35];
            [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:11]} forState:UIControlStateSelected];
            [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.7 alpha:1.0], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
        }
        [self.segmentedControl addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:self.segmentedControl];

        // ScrollView
        CGFloat scrollY = 104;
        CGFloat scrollH = h - scrollY - 8;
        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(14, scrollY, w - 28, scrollH)];
        self.scrollView.showsVerticalScrollIndicator = YES;
        self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        [self addSubview:self.scrollView];

        [self refreshCheatsList];
    }
    return self;
}

- (void)showToast:(NSString *)message {
    [self.toastTimer invalidate];
    self.toastLabel.text = message;
    [UIView animateWithDuration:0.2 animations:^{
        self.toastLabel.alpha = 1.0;
    }];
    self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:1.6 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [UIView animateWithDuration:0.3 animations:^{
            self.toastLabel.alpha = 0.0;
        }];
    }];
}

- (void)toggleVisibility {
    if (self.hidden) {
        self.hidden = NO;
        self.transform = CGAffineTransformMakeScale(0.85, 0.85);
        self.alpha = 0.0;
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.transform = CGAffineTransformIdentity;
            self.alpha = 1.0;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.transform = CGAffineTransformMakeScale(0.88, 0.88);
            self.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.hidden = YES;
        }];
    }
}

- (void)closeTapped {
    [self toggleVisibility];
}

- (void)categoryChanged:(UISegmentedControl *)sender {
    [self refreshCheatsList];
}

- (void)refreshCheatsList {
    for (UIView *sub in [self.scrollView.subviews copy]) {
        [sub removeFromSuperview];
    }

    NSInteger cat = self.segmentedControl.selectedSegmentIndex;
    NSArray *items = nil;

    if (cat == 0) {
        // Asosiy (Player)
        items = @[
            @{@"title": @"❤️ Cheksiz Jon (God Mode)", @"badge": @"FAOL", @"off": @(0xade84), @"msg": @"✅ Cheksiz Jon (God Mode) faollashtirildi!"},
            @{@"title": @"💰 HESOYAM ($250,000 + Jon + Bronya)", @"badge": @"BERISH", @"off": @(0xad3d4), @"msg": @"✅ $250,000 va Bronya berildi!"},
            @{@"title": @"♾️ Cheksiz O'q-Dori (Infinite Ammo)", @"badge": @"FAOL", @"off": @(0xade3c), @"msg": @"✅ Cheksiz O'q-Dori yoqildi!"},
            @{@"title": @"🚀 Jetpack Chiqarish", @"badge": @"SPAWN", @"off": @(0xad6fc), @"msg": @"✅ Jetpack chiqarildi!"},
            @{@"title": @"⚡ Tez Harakat (Fast Motion)", @"badge": @"FAOL", @"off": @(0xae76c), @"msg": @"✅ Tez harakat faollashtirildi!"}
        ];
    } else if (cat == 1) {
        // Qurollar (Weapons)
        items = @[
            @{@"title": @"🔫 Qurollar To'plami 1 (Kastet, Bita, Pistol)", @"badge": @"BERISH", @"off": @(0xacc80), @"msg": @"✅ 1-To'plam qurollari berildi!"},
            @{@"title": @"💣 Qurollar To'plami 2 (Deagle, Spas, MP5, M4)", @"badge": @"BERISH", @"off": @(0xacf40), @"msg": @"✅ 2-To'plam qurollari berildi!"},
            @{@"title": @"🚀 Qurollar To'plami 3 (Minigun, Bazuka, Pila)", @"badge": @"BERISH", @"off": @(0xad1c4), @"msg": @"✅ 3-To'plam qurollari berildi!"}
        ];
    } else if (cat == 2) {
        // Politsiya (Police / Wanted)
        items = @[
            @{@"title": @"🚫 Qidiruvni O'chirish (0 Yulduz)", @"badge": @"QULFLASH", @"off": @(0xadecc), @"msg": @"✅ Qidiruv 0 ga qulflab qo'yildi!"},
            @{@"title": @"⭐ Qidiruvni Pasaytirish (-1 Yulduz)", @"badge": @"PASAYTIRISH", @"off": @(0xad4b8), @"msg": @"✅ Qidiruv 1 darajaga kamaytirildi!"},
            @{@"title": @"🚨 Qidiruvni Ko'tarish (+1 Yulduz)", @"badge": @"OSHIRISH", @"off": @(0xad488), @"msg": @"✅ Qidiruv 1 darajaga oshirildi!"},
            @{@"title": @"⭐️ 6 Yulduz Qidiruv (Maksimal)", @"badge": @"MAX", @"off": @(0xadedc), @"msg": @"✅ 6 Yulduz qidiruv berildi!"}
        ];
    } else if (cat == 3) {
        // Mashinalar (Vehicles)
        items = @[
            @{@"title": @"🚗 Rhino Tank Chiqarish", @"badge": @"SPAWN", @"off": @(0xad5f0), @"msg": @"✅ Rhino Tank paydo bo'ldi!"},
            @{@"title": @"✈️ Hydra Qiruvchi Samolyot", @"badge": @"SPAWN", @"off": @(0xae398), @"msg": @"✅ Hydra Jet paydo bo'ldi!"},
            @{@"title": @"🚁 Hunter Jangovar Vertolyot", @"badge": @"SPAWN", @"off": @(0xae4c4), @"msg": @"✅ Hunter Vertolyot paydo bo'ldi!"},
            @{@"title": @"🚙 Monster Truck Chiqarish", @"badge": @"SPAWN", @"off": @(0xae1cc), @"msg": @"✅ Monster Truck paydo bo'ldi!"},
            @{@"title": @"🚤 Vortex Havo Yostiqli Kema", @"badge": @"SPAWN", @"off": @(0xae454), @"msg": @"✅ Vortex Kema paydo bo'ldi!"},
            @{@"title": @"💥 Barcha Mashinalarni Portlatish", @"badge": @"BOOM", @"off": @(0xad66c), @"msg": @"💥 Barcha mashinalar portlatildi!"}
        ];
    }

    CGFloat btnW = self.scrollView.bounds.size.width;
    CGFloat btnH = 36.0;
    CGFloat gap = 6.0;
    CGFloat curY = 2.0;

    for (int i = 0; i < items.count; i++) {
        NSDictionary *dict = items[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, curY, btnW, btnH);
        btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
        btn.layer.cornerRadius = 8.0;
        btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
        btn.layer.borderWidth = 0.8;
        btn.clipsToBounds = YES;
        btn.tag = i;

        // Label
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, btnW - 80, btnH)];
        lbl.text = dict[@"title"];
        lbl.font = [UIFont boldSystemFontOfSize:12];
        lbl.textColor = [UIColor whiteColor];
        lbl.userInteractionEnabled = NO;
        [btn addSubview:lbl];

        // Badge
        UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btnW - 68, (btnH - 18) / 2.0, 60, 18)];
        badge.text = dict[@"badge"];
        badge.font = [UIFont boldSystemFontOfSize:9];
        badge.textColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.15];
        badge.layer.cornerRadius = 4;
        badge.clipsToBounds = YES;
        badge.userInteractionEnabled = NO;
        [btn addSubview:badge];

        // Action
        objc_setAssociatedObject(btn, "cheat_info", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(cheatButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        [self.scrollView addSubview:btn];
        curY += btnH + gap;
    }

    self.scrollView.contentSize = CGSizeMake(btnW, curY + 6.0);
}

- (void)cheatButtonTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "cheat_info");
    if (!dict) return;

    uintptr_t off = [dict[@"off"] unsignedIntegerValue];
    NSString *msg = dict[@"msg"];

    // Haptic feedback
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    // Flash button feedback
    UIColor *origBg = sender.backgroundColor;
    sender.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.32 alpha:1.0];
    [UIView animateWithDuration:0.25 animations:^{
        sender.backgroundColor = origBg;
    }];

    // Trigger GTA native cheat
    trigger_native_cheat(off);

    // Show toast confirmation
    [self showToast:msg];
}

@end

// -----------------------------------------------------------------------------
// Setup & Dynamic Loading
// -----------------------------------------------------------------------------
static void setup_diro_ui(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[DIRO] Launching Diro Mod Menu overlay...");
            UIWindow *window = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                        window = [[DiroWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                        break;
                    }
                }
            }
            if (!window) {
                window = [[DiroWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            }
            g_diroWindow = (DiroWindow *)window;

            DiroRootViewController *vc = [[DiroRootViewController alloc] init];
            window.rootViewController = vc;
            window.hidden = NO;

            CGSize sz = [UIScreen mainScreen].bounds.size;
            CGFloat btnSize = 52.0;
            CGFloat initialX = 14.0;
            CGFloat initialY = (sz.height - btnSize) / 2.0;
            g_floatingButton = [[DiroFloatingButton alloc] initWithFrame:CGRectMake(initialX, initialY, btnSize, btnSize)];
            [vc.view addSubview:g_floatingButton];

            CGFloat mw = MIN(380.0, sz.width - 24.0);
            CGFloat mh = MIN(290.0, sz.height - 24.0);
            CGFloat mx = (sz.width - mw) / 2.0;
            CGFloat my = (sz.height - mh) / 2.0;
            g_menuModal = [[DiroMenuModal alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
            g_menuModal.hidden = YES;
            g_menuModal.alpha = 0.0;
            [vc.view addSubview:g_menuModal];

            NSLog(@"[DIRO] Diro Mod Menu is 100%% active and visible on screen!");
        });
    });
}

// Constructor: Executes automatically when GTASA.dylib is loaded by dyld
__attribute__((constructor))
static void diro_entry(void) {
    NSLog(@"[DIRO] GTASA.dylib (Diro Mod Menu) successfully loaded into GTA SA process!");

    // Setup UI when application finishes launching
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        setup_diro_ui();
    }];

    // Also fallback dispatch after 2.0 seconds in case notification already passed
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    // In addition, attach a background heartbeat to verify window is alive
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!g_diroWindow || g_diroWindow.hidden) {
            setup_diro_ui();
        }
    });
}
