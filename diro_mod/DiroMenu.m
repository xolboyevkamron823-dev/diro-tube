#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

@class DiroFloatingButton;

@interface DiroMenuModal : UIView
- (void)toggleVisibility;
@end

@interface DiroFloatingButton : UIView
@end

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
        case 488: return @"News Chopper";
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
        case 502: return @"Hotring A";
        case 503: return @"Hotring B";
        case 504: return @"Bloodring";
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
        case 523: return @"HPV1000";
        case 524: return @"Cement";
        case 525: return @"Towtruck";
        case 526: return @"Fortune";
        case 527: return @"Cadrona";
        case 528: return @"FBI Truck";
        case 529: return @"Willard";
        case 530: return @"Forklift";
        case 531: return @"Tractor";
        case 532: return @"Combine";
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
        case 544: return @"Firetruck Ladder";
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
        case 585: return @"Emperor";
        case 586: return @"Wayfarer";
        case 587: return @"Euros";
        case 588: return @"Hotdog";
        case 589: return @"Club";
        case 592: return @"Andromada";
        case 593: return @"Dodo";
        case 594: return @"RC Cam";
        case 595: return @"Launch";
        case 596: return @"Police LS";
        case 597: return @"Police SF";
        case 598: return @"Police LV";
        case 599: return @"Police Ranger";
        case 600: return @"Picador";
        case 601: return @"SWAT Van";
        case 602: return @"Alpha";
        case 603: return @"Phoenix";
        default: return [NSString stringWithFormat:@"Vehicle %d", modelId];
    }
}

// -----------------------------------------------------------------------------
// DiroFloatingButton: Movable circular button
// -----------------------------------------------------------------------------
@implementation DiroFloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.95];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0].CGColor;
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
// DiroMenuModal: Sleek dark acrylic cheat hub
// -----------------------------------------------------------------------------
@interface DiroMenuModal () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subTitleLabel;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSTimer *toastTimer;
@property (nonatomic, strong) UITextField *idTextField;
- (void)showToast:(NSString *)message;
- (void)refreshCheatsList;
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

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, w - 60, 20)];
        self.titleLabel.text = @"👑 DIRO MOD MENU";
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        self.titleLabel.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [self addSubview:self.titleLabel];

        self.subTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, w - 60, 14)];
        self.subTitleLabel.text = @"100% Offline • Ro'yxatdan o'tish shart emas";
        self.subTitleLabel.font = [UIFont systemFontOfSize:10];
        self.subTitleLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        [self addSubview:self.subTitleLabel];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(w - 38, 10, 28, 28);
        closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        closeBtn.layer.cornerRadius = 14;
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [closeBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];

        self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 46, w - 28, 18)];
        self.toastLabel.textAlignment = NSTextAlignmentCenter;
        self.toastLabel.font = [UIFont boldSystemFontOfSize:11];
        self.toastLabel.textColor = [UIColor colorWithRed:0.20 green:0.95 blue:0.45 alpha:1.0];
        self.toastLabel.alpha = 0.0;
        [self addSubview:self.toastLabel];

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

        CGFloat scrollY = 104;
        CGFloat scrollH = h - scrollY - 8;
        self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(14, scrollY, w - 28, scrollH)];
        self.scrollView.showsVerticalScrollIndicator = YES;
        self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        [self addSubview:self.scrollView];

        UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
        bgTap.cancelsTouchesInView = NO;
        [self addGestureRecognizer:bgTap];

        [self refreshCheatsList];
    }
    return self;
}

- (void)dismissKeyboard {
    [self endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self spawnByIdTapped];
    return YES;
}

- (void)showToast:(NSString *)message {
    [self.toastTimer invalidate];
    self.toastLabel.text = message;
    [UIView animateWithDuration:0.2 animations:^{
        self.toastLabel.alpha = 1.0;
    }];
    self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:1.8 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [UIView animateWithDuration:0.3 animations:^{
            self.toastLabel.alpha = 0.0;
        }];
    }];
}

- (void)toggleVisibility {
    [self endEditing:YES];
    if (self.hidden) {
        UIView *sv = self.superview;
        if (sv) {
            CGFloat mw = MIN(380.0, sv.bounds.size.width - 24.0);
            CGFloat mh = MIN(290.0, sv.bounds.size.height - 24.0);
            self.frame = CGRectMake((sv.bounds.size.width - mw) / 2.0, (sv.bounds.size.height - mh) / 2.0, mw, mh);
            [sv bringSubviewToFront:self];
        }
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
    [self endEditing:YES];
    [self refreshCheatsList];
}

- (void)refreshCheatsList {
    for (UIView *sub in [self.scrollView.subviews copy]) {
        [sub removeFromSuperview];
    }

    NSInteger cat = self.segmentedControl.selectedSegmentIndex;
    CGFloat btnW = self.scrollView.bounds.size.width;
    CGFloat curY = 2.0;

    if (cat == 3) {
        UIView *idBar = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 40.0)];
        idBar.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:1.0];
        idBar.layer.cornerRadius = 8.0;
        idBar.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.8].CGColor;
        idBar.layer.borderWidth = 1.0;
        idBar.clipsToBounds = YES;

        UILabel *idLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 50, 40)];
        idLbl.text = @"🆔 ID:";
        idLbl.font = [UIFont boldSystemFontOfSize:12];
        idLbl.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [idBar addSubview:idLbl];

        self.idTextField = [[UITextField alloc] initWithFrame:CGRectMake(60, 6, btnW - 160, 28)];
        self.idTextField.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0];
        self.idTextField.layer.cornerRadius = 6.0;
        self.idTextField.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
        self.idTextField.layer.borderWidth = 0.8;
        self.idTextField.textColor = [UIColor whiteColor];
        self.idTextField.font = [UIFont boldSystemFontOfSize:13];
        self.idTextField.textAlignment = NSTextAlignmentCenter;
        self.idTextField.placeholder = @"400-611";
        self.idTextField.keyboardType = UIKeyboardTypeNumberPad;
        self.idTextField.returnKeyType = UIReturnKeyDone;
        self.idTextField.delegate = self;
        [idBar addSubview:self.idTextField];

        UIButton *spawnBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        spawnBtn.frame = CGRectMake(btnW - 92, 6, 84, 28);
        spawnBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        spawnBtn.layer.cornerRadius = 6.0;
        [spawnBtn setTitle:@"🚗 SPAWN" forState:UIControlStateNormal];
        spawnBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [spawnBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [spawnBtn addTarget:self action:@selector(spawnByIdTapped) forControlEvents:UIControlEventTouchUpInside];
        [idBar addSubview:spawnBtn];

        [self.scrollView addSubview:idBar];
        curY += 46.0;

        NSArray *vList = @[
            @{@"title": @"🏎️ Infernus (ID: 411)", @"badge": @"SPAWN", @"vid": @(411)},
            @{@"title": @"🏎️ Bullet (ID: 541)", @"badge": @"SPAWN", @"vid": @(541)},
            @{@"title": @"🏎️ Sultan (ID: 560)", @"badge": @"SPAWN", @"vid": @(560)},
            @{@"title": @"🏎️ Elegy (ID: 562)", @"badge": @"SPAWN", @"vid": @(562)},
            @{@"title": @"🏎️ Cheetah (ID: 415)", @"badge": @"SPAWN", @"vid": @(415)},
            @{@"title": @"🏎️ Turismo (ID: 451)", @"badge": @"SPAWN", @"vid": @(451)},
            @{@"title": @"🏍️ NRG-500 Sportbayk (ID: 522)", @"badge": @"SPAWN", @"vid": @(522)},
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
    if (cat == 0) {
        items = @[
            @{@"title": @"❤️ Cheksiz Jon (God Mode)", @"badge": @"FAOL", @"off": @(0xade84), @"msg": @"✅ Cheksiz Jon (God Mode) faollashtirildi!"},
            @{@"title": @"💰 HESOYAM ($250,000 + Jon + Bronya)", @"badge": @"BERISH", @"off": @(0xad3d4), @"msg": @"✅ $250,000 va Bronya berildi!"},
            @{@"title": @"♾️ Cheksiz O'q-Dori (Infinite Ammo)", @"badge": @"FAOL", @"off": @(0xade3c), @"msg": @"✅ Cheksiz O'q-Dori yoqildi!"},
            @{@"title": @"🚀 Jetpack Chiqarish", @"badge": @"SPAWN", @"off": @(0xad6fc), @"msg": @"✅ Jetpack chiqarildi!"},
            @{@"title": @"⚡ Tez Harakat (Fast Motion)", @"badge": @"FAOL", @"off": @(0xae76c), @"msg": @"✅ Tez harakat faollashtirildi!"}
        ];
    } else if (cat == 1) {
        items = @[
            @{@"title": @"🔫 Qurollar To'plami 1 (Kastet, Bita, Pistol)", @"badge": @"BERISH", @"off": @(0xacc80), @"msg": @"✅ 1-To'plam qurollari berildi!"},
            @{@"title": @"💣 Qurollar To'plami 2 (Deagle, Spas, MP5, M4)", @"badge": @"BERISH", @"off": @(0xacf40), @"msg": @"✅ 2-To'plam qurollari berildi!"},
            @{@"title": @"🚀 Qurollar To'plami 3 (Minigun, Bazuka, Pila)", @"badge": @"BERISH", @"off": @(0xad1c4), @"msg": @"✅ 3-To'plam qurollari berildi!"}
        ];
    } else if (cat == 2) {
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
// Direct Game Window Attachment with Periodic Repositioning
// -----------------------------------------------------------------------------
static void check_and_reposition(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;

    UIWindow *w = app.keyWindow;
    if (!w && app.windows.count > 0) {
        w = app.windows.firstObject;
    }
    if (!w) return;

    CGRect b = w.bounds;
    if (b.size.width < 50 || b.size.height < 50) return;

    if (!g_floatingButton || g_floatingButton.superview != w) {
        if (g_floatingButton) [g_floatingButton removeFromSuperview];
        if (g_menuModal) [g_menuModal removeFromSuperview];

        CGFloat btnSize = 52.0;
        CGFloat initialX = 14.0;
        CGFloat initialY = (b.size.height - btnSize) / 2.0;

        if (!g_floatingButton) {
            g_floatingButton = [[DiroFloatingButton alloc] initWithFrame:CGRectMake(initialX, initialY, btnSize, btnSize)];
        }
        [w addSubview:g_floatingButton];
        [w bringSubviewToFront:g_floatingButton];

        CGFloat mw = MIN(380.0, b.size.width - 24.0);
        CGFloat mh = MIN(290.0, b.size.height - 24.0);
        CGFloat mx = (b.size.width - mw) / 2.0;
        CGFloat my = (b.size.height - mh) / 2.0;

        if (!g_menuModal) {
            g_menuModal = [[DiroMenuModal alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
            g_menuModal.hidden = YES;
            g_menuModal.alpha = 0.0;
        }
        [w addSubview:g_menuModal];
        [w bringSubviewToFront:g_menuModal];

        NSLog(@"[DIRO] Diro UI attached to active game window (%.0fx%.0f)", b.size.width, b.size.height);
    } else {
        [w bringSubviewToFront:g_floatingButton];
        if (g_menuModal && !g_menuModal.hidden) {
            [w bringSubviewToFront:g_menuModal];
        }
    }
}

__attribute__((constructor))
static void diro_entry(void) {
    NSLog(@"[DIRO] DiroMenu.dylib initialized!");

    // Periodic check every 1.5s using GCD timer
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), (uint64_t)(1.5 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        check_and_reposition();
    });
    dispatch_resume(timer);
}
