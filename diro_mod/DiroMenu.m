#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>

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

// Safe native cheat callers using ASLR slide
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

static void trigger_vehicle_cheat(int modelId) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0xaf4d4;
    void (*fn)(int) = (void(*)(int))addr;
    if (fn) {
        fn(modelId);
    }
}

// Vehicle names lookup
static NSString *get_vehicle_name(int modelId) {
    switch (modelId) {
        case 400: return @"Landstalker";
        case 401: return @"Bravura";
        case 402: return @"Buffalo";
        case 403: return @"Linerunner";
        case 404: return @"Perennial";
        case 405: return @"Sentinel";
        case 406: return @"Dumper";
        case 407: return @"Firetruck";
        case 408: return @"Trashmaster";
        case 409: return @"Stretch";
        case 410: return @"Manana";
        case 411: return @"Infernus";
        case 412: return @"Voodoo";
        case 413: return @"Pony";
        case 414: return @"Mule";
        case 415: return @"Cheetah";
        case 416: return @"Ambulance";
        case 417: return @"Leviathan";
        case 418: return @"Moonbeam";
        case 419: return @"Esperanto";
        case 420: return @"Taxi";
        case 421: return @"Washington";
        case 422: return @"Bobcat";
        case 423: return @"Mr Whoopee";
        case 424: return @"BF Injection";
        case 425: return @"Hunter";
        case 426: return @"Premier";
        case 427: return @"Enforcer";
        case 428: return @"Securicar";
        case 429: return @"Banshee";
        case 430: return @"Predator";
        case 431: return @"Bus";
        case 432: return @"Rhino";
        case 433: return @"Barracks";
        case 434: return @"Hotknife";
        case 436: return @"Previon";
        case 437: return @"Coach";
        case 438: return @"Cabbie";
        case 439: return @"Stallion";
        case 440: return @"Rumpo";
        case 441: return @"RC Bandit";
        case 442: return @"Romero";
        case 443: return @"Packer";
        case 444: return @"Monster";
        case 445: return @"Admiral";
        case 446: return @"Squalo";
        case 447: return @"Seasparrow";
        case 448: return @"Pizzaboy";
        case 449: return @"Tram";
        case 451: return @"Turismo";
        case 452: return @"Speeder";
        case 453: return @"Reefer";
        case 454: return @"Tropic";
        case 455: return @"Flatbed";
        case 456: return @"Yankee";
        case 457: return @"Caddy";
        case 458: return @"Solair";
        case 459: return @"Berkley's RC Van";
        case 460: return @"Skimmer";
        case 461: return @"PCJ-600";
        case 462: return @"Faggio";
        case 463: return @"Freeway";
        case 464: return @"RC Baron";
        case 465: return @"RC Raider";
        case 466: return @"Glendale";
        case 467: return @"Oceanic";
        case 468: return @"Sanchez";
        case 469: return @"Sparrow";
        case 470: return @"Patriot";
        case 471: return @"Quad";
        case 472: return @"Coastguard";
        case 473: return @"Dinghy";
        case 474: return @"Hermes";
        case 475: return @"Sabre";
        case 476: return @"Rustler";
        case 477: return @"ZR-350";
        case 478: return @"Walton";
        case 479: return @"Regina";
        case 480: return @"Comet";
        case 481: return @"BMX";
        case 482: return @"Burrito";
        case 483: return @"Camper";
        case 484: return @"Marquis";
        case 485: return @"Baggage";
        case 486: return @"Dozer";
        case 487: return @"Maverick";
        case 488: return @"News Maverick";
        case 489: return @"Rancher";
        case 490: return @"FBI Rancher";
        case 491: return @"Virgo";
        case 492: return @"Greenwood";
        case 493: return @"Jetmax";
        case 494: return @"Hotring";
        case 495: return @"Sandking";
        case 496: return @"Blista Compact";
        case 497: return @"Police Maverick";
        case 498: return @"Boxville";
        case 499: return @"Benson";
        case 500: return @"Mesa";
        case 501: return @"RC Goblin";
        case 502: return @"Hotring Racer A";
        case 503: return @"Hotring Racer B";
        case 504: return @"Bloodring Banger";
        case 505: return @"Rancher";
        case 506: return @"Super GT";
        case 507: return @"Elegant";
        case 508: return @"Journey";
        case 509: return @"Bike";
        case 510: return @"Mountain Bike";
        case 511: return @"Beagle";
        case 512: return @"Cropduster";
        case 513: return @"Stuntplane";
        case 514: return @"Tanker";
        case 515: return @"Roadtrain";
        case 516: return @"Nebula";
        case 517: return @"Majestic";
        case 518: return @"Buccaneer";
        case 519: return @"Shamal";
        case 520: return @"Hydra";
        case 521: return @"FCR-900";
        case 522: return @"NRG-500";
        case 523: return @"HPV-1000";
        case 524: return @"Cement Truck";
        case 525: return @"Towtruck";
        case 526: return @"Fortune";
        case 527: return @"Cadrona";
        case 528: return @"FBI Truck";
        case 529: return @"Willard";
        case 530: return @"Forklift";
        case 531: return @"Tractor";
        case 532: return @"Combine Harvester";
        case 533: return @"Feltzer";
        case 534: return @"Remington";
        case 535: return @"Slamvan";
        case 536: return @"Blade";
        case 537: return @"Freight";
        case 538: return @"Streak";
        case 539: return @"Vortex";
        case 540: return @"Vincent";
        case 541: return @"Bullet";
        case 542: return @"Clover";
        case 543: return @"Sadler";
        case 544: return @"Firetruck LA";
        case 545: return @"Hustler";
        case 546: return @"Intruder";
        case 547: return @"Primo";
        case 548: return @"Cargobob";
        case 549: return @"Tampa";
        case 550: return @"Sunrise";
        case 551: return @"Merit";
        case 552: return @"Utility";
        case 553: return @"Nevada";
        case 554: return @"Yosemite";
        case 555: return @"Windsor";
        case 556: return @"Monster A";
        case 557: return @"Monster B";
        case 558: return @"Uranus";
        case 559: return @"Jester";
        case 560: return @"Sultan";
        case 561: return @"Stratum";
        case 562: return @"Elegy";
        case 563: return @"Raindance";
        case 564: return @"RC Tiger";
        case 565: return @"Flash";
        case 566: return @"Tahoma";
        case 567: return @"Savanna";
        case 568: return @"Bandito";
        case 569: return @"Freight Flat";
        case 570: return @"Streak Carriage";
        case 571: return @"Kart";
        case 572: return @"Mower";
        case 573: return @"Dune";
        case 574: return @"Sweeper";
        case 575: return @"Broadway";
        case 576: return @"Tornado";
        case 577: return @"AT-400";
        case 578: return @"DFT-30";
        case 579: return @"Huntley";
        case 580: return @"Stafford";
        case 581: return @"BF-400";
        case 582: return @"Newsvan";
        case 583: return @"Tug";
        case 584: return @"Petrol Trailer";
        case 585: return @"Emperor";
        case 586: return @"Wayfarer";
        case 587: return @"Euros";
        case 588: return @"Hotdog";
        case 589: return @"Club";
        case 590: return @"Freight Box";
        case 591: return @"Trailer 3";
        case 592: return @"Andromada";
        case 593: return @"Dodo";
        case 594: return @"RC Cam";
        case 595: return @"Launch";
        case 596: return @"Police Car (LSPD)";
        case 597: return @"Police Car (SFPD)";
        case 598: return @"Police Car (LVPD)";
        case 599: return @"Police Ranger";
        case 600: return @"Picador";
        case 601: return @"S.W.A.T. Van";
        case 602: return @"Alpha";
        case 603: return @"Phoenix";
        case 604: return @"Glendale Damaged";
        case 605: return @"Sadler Damaged";
        case 606: return @"Baggage Trailer A";
        case 607: return @"Baggage Trailer B";
        case 608: return @"Tug Stairs";
        case 609: return @"Boxville Black";
        case 610: return @"Farm Trailer";
        case 611: return @"Street Clean Trailer";
        default: return [NSString stringWithFormat:@"Vehicle_%d", modelId];
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
        [g_menuModal performSelector:@selector(toggleVisibility)];
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
@interface DiroMenuModal () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subTitleLabel;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *idTextField;
@property (nonatomic, strong) NSTimer *toastTimer;
@end

@implementation DiroMenuModal

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:0.96];
        self.layer.cornerRadius = 14.0;
        self.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.8].CGColor;
        self.layer.borderWidth = 1.5;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 10);
        self.layer.shadowOpacity = 0.9;
        self.layer.shadowRadius = 16.0;
        self.clipsToBounds = YES;

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    CGFloat w = self.bounds.size.width;

    // Header container
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    headerView.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.14 alpha:1.0];
    [self addSubview:headerView];

    // Crown Icon & Title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, w - 60, 20)];
    self.titleLabel.text = @"👑 DIRO MOD MENU";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
    [headerView addSubview:self.titleLabel];

    // Subtitle
    self.subTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 24, w - 60, 14)];
    self.subTitleLabel.text = @"GTA San Andreas iOS • 100% Oflayn & Tekin";
    self.subTitleLabel.font = [UIFont systemFontOfSize:10];
    self.subTitleLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [headerView addSubview:self.subTitleLabel];

    // Close button (X)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 38, 6, 32, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleVisibility) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:closeBtn];

    // Toast status notification banner
    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 48, w - 20, 20)];
    self.toastLabel.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:0.25];
    self.toastLabel.layer.cornerRadius = 4;
    self.toastLabel.layer.borderColor = [UIColor colorWithRed:0.15 green:0.80 blue:0.40 alpha:0.8].CGColor;
    self.toastLabel.layer.borderWidth = 0.8;
    self.toastLabel.clipsToBounds = YES;
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    self.toastLabel.font = [UIFont boldSystemFontOfSize:11];
    self.toastLabel.textColor = [UIColor colorWithRed:0.30 green:1.00 blue:0.50 alpha:1.0];
    self.toastLabel.hidden = YES;
    [self addSubview:self.toastLabel];

    // Category segmented control
    NSArray *categories = @[@"🚗 Avtolar", @"🛡️ O'yinchi", @"🔫 Qurollar", @"🚓 Qidiruv"];
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:categories];
    self.segmentedControl.frame = CGRectMake(10, 72, w - 20, 28);
    self.segmentedControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *)) {
        self.segmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.85];
        [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:11]} forState:UIControlStateSelected];
        [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11]} forState:UIControlStateNormal];
    } else {
        self.segmentedControl.tintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
    }
    [self.segmentedControl addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.segmentedControl];

    // Scrollable cheat list
    CGFloat listY = 106.0;
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, listY, w - 20, self.bounds.size.height - listY - 8.0)];
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.alwaysBounceVertical = YES;
    [self addSubview:self.scrollView];

    [self refreshCheatsList];
}

- (void)toggleVisibility {
    BOOL shouldOpen = self.hidden;
    if (shouldOpen) {
        self.transform = CGAffineTransformMakeScale(0.85, 0.85);
        self.alpha = 0.0;
        self.hidden = NO;
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.transform = CGAffineTransformIdentity;
            self.alpha = 1.0;
        } completion:nil];
    } else {
        [self.idTextField resignFirstResponder];
        [UIView animateWithDuration:0.2 animations:^{
            self.transform = CGAffineTransformMakeScale(0.85, 0.85);
            self.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.hidden = YES;
            self.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)showToast:(NSString *)message {
    [self.toastTimer invalidate];
    self.toastLabel.text = message;
    self.toastLabel.alpha = 0.0;
    self.toastLabel.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{
        self.toastLabel.alpha = 1.0;
    }];

    self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 target:self selector:@selector(hideToast) userInfo:nil repeats:NO];
}

- (void)hideToast {
    [UIView animateWithDuration:0.3 animations:^{
        self.toastLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.toastLabel.hidden = YES;
    }];
}

- (void)categoryChanged:(UISegmentedControl *)sender {
    [self.idTextField resignFirstResponder];
    [self refreshCheatsList];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self spawnByIdTapped];
    return YES;
}

- (void)refreshCheatsList {
    for (UIView *v in self.scrollView.subviews) {
        [v removeFromSuperview];
    }

    NSInteger cat = self.segmentedControl.selectedSegmentIndex;
    CGFloat btnW = self.scrollView.bounds.size.width;
    CGFloat curY = 0.0;

    // Category 0: Vehicles + ID Spawner
    if (cat == 0) {
        // Vehicle Spawner Card
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 76)];
        card.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:1.0];
        card.layer.cornerRadius = 8.0;
        card.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.6].CGColor;
        card.layer.borderWidth = 1.0;
        card.clipsToBounds = YES;

        UILabel *cardTitle = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, btnW - 16, 16)];
        cardTitle.text = @"🆔 Mashina ID bo'yicha chiqarish (400 - 611):";
        cardTitle.font = [UIFont boldSystemFontOfSize:11];
        cardTitle.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [card addSubview:cardTitle];

        // TextField
        self.idTextField = [[UITextField alloc] initWithFrame:CGRectMake(8, 28, btnW - 110, 38)];
        self.idTextField.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        self.idTextField.layer.cornerRadius = 6;
        self.idTextField.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
        self.idTextField.layer.borderWidth = 0.8;
        self.idTextField.textColor = [UIColor whiteColor];
        self.idTextField.font = [UIFont boldSystemFontOfSize:14];
        self.idTextField.placeholder = @"Masalan: 411";
        self.idTextField.keyboardType = UIKeyboardTypeNumberPad;
        self.idTextField.textAlignment = NSTextAlignmentCenter;
        self.idTextField.delegate = self;
        if (@available(iOS 13.0, *)) {
            self.idTextField.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        [card addSubview:self.idTextField];

        // Spawn Button
        UIButton *spawnBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        spawnBtn.frame = CGRectMake(btnW - 96, 28, 88, 38);
        spawnBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        spawnBtn.layer.cornerRadius = 6;
        [spawnBtn setTitle:@"🚗 SPAWN" forState:UIControlStateNormal];
        [spawnBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        spawnBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [spawnBtn addTarget:self action:@selector(spawnByIdTapped) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:spawnBtn];

        [self.scrollView addSubview:card];
        curY += 82.0;

        // Quick popular vehicles list
        NSArray *vList = @[
            @{@"title": @"🏎️ Infernus Sportkar (ID: 411)", @"badge": @"SPAWN", @"vid": @(411)},
            @{@"title": @"🏎️ Bullet Superkar (ID: 541)", @"badge": @"SPAWN", @"vid": @(541)},
            @{@"title": @"🏎️ Cheetah (ID: 415)", @"badge": @"SPAWN", @"vid": @(415)},
            @{@"title": @"🏎️ Turismo (ID: 451)", @"badge": @"SPAWN", @"vid": @(451)},
            @{@"title": @"🏎️ Banshee (ID: 429)", @"badge": @"SPAWN", @"vid": @(429)},
            @{@"title": @"🚗 Sultan 4-Eshik Drift (ID: 560)", @"badge": @"SPAWN", @"vid": @(560)},
            @{@"title": @"🚗 Elegy Drift (ID: 562)", @"badge": @"SPAWN", @"vid": @(562)},
            @{@"title": @"🚗 Buffalo (ID: 402)", @"badge": @"SPAWN", @"vid": @(402)},
            @{@"title": @"🚗 Jester Tyuning (ID: 559)", @"badge": @"SPAWN", @"vid": @(559)},
            @{@"title": @"🏍️ NRG-500 Tezkor Mototsikl (ID: 522)", @"badge": @"SPAWN", @"vid": @(522)},
            @{@"title": @"🏍️ Sanchez Krossbayk (ID: 468)", @"badge": @"SPAWN", @"vid": @(468)},
            @{@"title": @"🚗 Rhino Tank (ID: 432)", @"badge": @"SPAWN", @"vid": @(432)},
            @{@"title": @"✈️ Hydra Qiruvchi Samolyot (ID: 520)", @"badge": @"SPAWN", @"vid": @(520)},
            @{@"title": @"🚁 Hunter Vertolyot (ID: 425)", @"badge": @"SPAWN", @"vid": @(425)},
            @{@"title": @"🚙 Monster Truck (ID: 444)", @"badge": @"SPAWN", @"vid": @(444)},
            @{@"title": @"🚤 Vortex Kema (ID: 539)", @"badge": @"SPAWN", @"vid": @(539)},
            @{@"title": @"💥 Barcha Mashinalarni Portlatish", @"badge": @"BOOM", @"off": @(0xad66c), @"msg": @"💥 Barcha mashinalar portlatildi!"}
        ];

        CGFloat btnH = 36.0;
        CGFloat gap = 6.0;
        for (NSDictionary *dict in vList) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(0, curY, btnW, btnH);
            btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
            btn.layer.borderWidth = 0.8;
            btn.clipsToBounds = YES;

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, btnW - 80, btnH)];
            lbl.text = dict[@"title"];
            lbl.font = [UIFont boldSystemFontOfSize:12];
            lbl.textColor = [UIColor whiteColor];
            lbl.userInteractionEnabled = NO;
            [btn addSubview:lbl];

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

            objc_setAssociatedObject(btn, "cheat_info", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(vehicleListButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
            curY += btnH + gap;
        }

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }

    NSArray *items = nil;
    if (cat == 1) {
        items = @[
            @{@"title": @"❤️ Cheksiz Jon (God Mode)", @"badge": @"FAOL", @"off": @(0xade84), @"msg": @"✅ Cheksiz Jon (God Mode) faollashtirildi!"},
            @{@"title": @"💰 HESOYAM ($250,000 + Jon + Bronya)", @"badge": @"BERISH", @"off": @(0xad3d4), @"msg": @"✅ $250,000 va Bronya berildi!"},
            @{@"title": @"♾️ Cheksiz O'q-Dori (Infinite Ammo)", @"badge": @"FAOL", @"off": @(0xade3c), @"msg": @"✅ Cheksiz O'q-Dori yoqildi!"},
            @{@"title": @"🚀 Jetpack Chiqarish", @"badge": @"SPAWN", @"off": @(0xad6fc), @"msg": @"✅ Jetpack chiqarildi!"},
            @{@"title": @"⚡ Tez Harakat (Fast Motion)", @"badge": @"FAOL", @"off": @(0xae76c), @"msg": @"✅ Tez harakat faollashtirildi!"}
        ];
    } else if (cat == 2) {
        items = @[
            @{@"title": @"🔫 Qurollar To'plami 1 (Kastet, Bita, Pistol)", @"badge": @"BERISH", @"off": @(0xacc80), @"msg": @"✅ 1-To'plam qurollari berildi!"},
            @{@"title": @"💣 Qurollar To'plami 2 (Deagle, Spas, MP5, M4)", @"badge": @"BERISH", @"off": @(0xacf40), @"msg": @"✅ 2-To'plam qurollari berildi!"},
            @{@"title": @"🚀 Qurollar To'plami 3 (Minigun, Bazuka, Pila)", @"badge": @"BERISH", @"off": @(0xad1c4), @"msg": @"✅ 3-To'plam qurollari berildi!"}
        ];
    } else if (cat == 3) {
        items = @[
            @{@"title": @"🚫 Qidiruvni O'chirish (0 Yulduz)", @"badge": @"QULFLASH", @"off": @(0xadecc), @"msg": @"✅ Qidiruv 0 ga qulflab qo'yildi!"},
            @{@"title": @"⭐ Qidiruvni Pasaytirish (-1 Yulduz)", @"badge": @"PASAYTIRISH", @"off": @(0xad4b8), @"msg": @"✅ Qidiruv 1 darajaga kamaytirildi!"},
            @{@"title": @"🚨 Qidiruvni Ko'tarish (+1 Yulduz)", @"badge": @"OSHIRISH", @"off": @(0xad488), @"msg": @"✅ Qidiruv 1 darajaga oshirildi!"},
            @{@"title": @"⭐️ 6 Yulduz Qidiruv (Maksimal)", @"badge": @"MAX", @"off": @(0xadedc), @"msg": @"✅ 6 Yulduz qidiruv berildi!"}
        ];
    }

    CGFloat btnH = 36.0;
    CGFloat gap = 6.0;

    for (NSDictionary *dict in items) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, curY, btnW, btnH);
        btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
        btn.layer.cornerRadius = 8.0;
        btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
        btn.layer.borderWidth = 0.8;
        btn.clipsToBounds = YES;

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, btnW - 80, btnH)];
        lbl.text = dict[@"title"];
        lbl.font = [UIFont boldSystemFontOfSize:12];
        lbl.textColor = [UIColor whiteColor];
        lbl.userInteractionEnabled = NO;
        [btn addSubview:lbl];

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

        objc_setAssociatedObject(btn, "cheat_info", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(cheatButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        [self.scrollView addSubview:btn];
        curY += btnH + gap;
    }

    self.scrollView.contentSize = CGSizeMake(btnW, curY + 6.0);
}

- (void)spawnByIdTapped {
    [self.idTextField resignFirstResponder];
    NSString *txt = [self.idTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (txt.length == 0) {
        [self showToast:@"⚠️ Mashina ID sini kiriting! (Masalan: 411)"];
        return;
    }

    int vid = [txt intValue];
    if (vid < 400 || vid > 611) {
        [self showToast:@"⚠️ ID 400 dan 611 oralig'ida bo'lishi kerak!"];
        return;
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen prepare];
        [gen impactOccurred];
    }

    trigger_vehicle_cheat(vid);
    NSString *vName = get_vehicle_name(vid);
    [self showToast:[NSString stringWithFormat:@"✅ Paydo bo'ldi: ID %d (%@)", vid, vName]];
}

- (void)vehicleListButtonTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "cheat_info");
    if (!dict) return;

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    if (dict[@"vid"]) {
        int vid = [dict[@"vid"] intValue];
        trigger_vehicle_cheat(vid);
        NSString *vName = get_vehicle_name(vid);
        [self showToast:[NSString stringWithFormat:@"✅ Paydo bo'ldi: ID %d (%@)", vid, vName]];
    } else if (dict[@"off"]) {
        uintptr_t off = [dict[@"off"] unsignedIntegerValue];
        trigger_native_cheat(off);
        [self showToast:dict[@"msg"]];
    }
}

- (void)cheatButtonTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "cheat_info");
    if (!dict) return;

    uintptr_t off = [dict[@"off"] unsignedIntegerValue];
    NSString *msg = dict[@"msg"];

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    UIColor *origBg = sender.backgroundColor;
    sender.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.32 alpha:1.0];
    [UIView animateWithDuration:0.25 animations:^{
        sender.backgroundColor = origBg;
    }];

    trigger_native_cheat(off);
    [self showToast:msg];
}

@end

// -----------------------------------------------------------------------------
// Setup & Dynamic Loading
// -----------------------------------------------------------------------------
static void setup_diro_ui(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_diroWindow && g_floatingButton && g_floatingButton.superview) {
            [g_diroWindow.rootViewController.view bringSubviewToFront:g_floatingButton];
            if (g_menuModal && !g_menuModal.hidden) {
                [g_diroWindow.rootViewController.view bringSubviewToFront:g_menuModal];
            }
            return;
        }

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
        if (!g_floatingButton) {
            g_floatingButton = [[DiroFloatingButton alloc] initWithFrame:CGRectMake(initialX, initialY, btnSize, btnSize)];
        }
        [vc.view addSubview:g_floatingButton];

        CGFloat mw = MIN(380.0, sz.width - 24.0);
        CGFloat mh = MIN(290.0, sz.height - 24.0);
        CGFloat mx = (sz.width - mw) / 2.0;
        CGFloat my = (sz.height - mh) / 2.0;
        if (!g_menuModal) {
            g_menuModal = [[DiroMenuModal alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
            g_menuModal.hidden = YES;
            g_menuModal.alpha = 0.0;
        }
        [vc.view addSubview:g_menuModal];

        // Hide legacy cheat windows if present
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w != g_diroWindow) {
                NSString *cls = NSStringFromClass([w class]);
                if ([cls containsString:@"ButtonWindow"] || [cls containsString:@"IGWindow"] || [cls containsString:@"IGFloating"]) {
                    w.hidden = YES;
                    w.alpha = 0.0;
                }
            }
        }

        NSLog(@"[DIRO] Diro Mod Menu is 100%% active and visible on screen!");
    });
}

// Constructor: Executes automatically when GTASA.dylib is loaded by dyld
__attribute__((constructor))
static void diro_entry(void) {
    NSLog(@"[DIRO] Diro GTASA.dylib successfully loaded into GTA SA process!");

    // 1. Load original engine dylib with GameCenterFix to ensure 100% loading stability
    NSString *origPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/GTASA_Original.dylib"];
    void *h = dlopen([origPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        h = dlopen("@executable_path/Frameworks/GTASA_Original.dylib", RTLD_NOW | RTLD_GLOBAL);
    }
    NSLog(@"[DIRO] Loaded GTASA_Original.dylib handle: %p", h);

    // 2. Setup UI when application finishes launching
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        setup_diro_ui();
    }];

    // Also fallback dispatch after 1.5, 3.0, and 5.0 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });
}
