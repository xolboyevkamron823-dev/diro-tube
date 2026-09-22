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

// -----------------------------------------------------------------------------
// ASLR Slide & Engine Pointers
// -----------------------------------------------------------------------------
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

// CPed* FindPlayerPed(int playerIndex = -1) at 0x190bfc
static uintptr_t get_player_ped(void) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x190bfc;
    uintptr_t (*fn)(int) = (uintptr_t(*)(int))addr;
    if (fn) {
        return fn(-1);
    }
    return 0;
}

static uintptr_t g_lastSpawnedVehicle = 0;

// CVehicle* FindPlayerVehicle(int playerIndex = -1, bool bIncludeRemote = false) at 0x190f1c
static uintptr_t get_player_vehicle(void) {
    uintptr_t ped = get_player_ped();
    if (ped) {
        uintptr_t v = *(uintptr_t *)(ped + 0x708);
        if (v) return v;
    }
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x190f1c;
    uintptr_t (*fn)(int, bool) = (uintptr_t(*)(int, bool))addr;
    if (fn) {
        return fn(-1, false);
    }
    return 0;
}

static uintptr_t get_current_or_last_vehicle(void) {
    uintptr_t v = get_player_vehicle();
    if (v) return v;
    if (g_lastSpawnedVehicle) return g_lastSpawnedVehicle;
    return 0;
}

// CCheat::VehicleCheat(int modelId) at 0xaf4d4
static void trigger_vehicle_cheat(int modelId) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0xaf4d4;
    uintptr_t (*fn)(int) = (uintptr_t(*)(int))addr;
    if (fn) {
        uintptr_t veh = fn(modelId);
        if (veh) {
            g_lastSpawnedVehicle = veh;
        }
    }
}

// Vehicle Color Changer: Sets primary and secondary colors at offsets 0x574, 0x575, 0x576, 0x577, global palette at 0x7e3532, and repaints clump materials via 0x231908
static BOOL change_vehicle_color(uint8_t primary, uint8_t secondary) {
    uintptr_t veh = get_current_or_last_vehicle();
    if (!veh) return NO;

    // 1. Write the 4 vehicle color slots directly at 0x574, 0x575, 0x576, 0x577
    *(uint8_t *)(veh + 0x574) = primary;
    *(uint8_t *)(veh + 0x575) = secondary;
    *(uint8_t *)(veh + 0x576) = primary;
    *(uint8_t *)(veh + 0x577) = secondary;

    // Direct backup at legacy offsets 0x17d, 0x17e
    *(uint8_t *)(veh + 0x17d) = primary;
    *(uint8_t *)(veh + 0x17e) = secondary;

    intptr_t slide = get_gtasa_slide();

    // 2. Set global palette indices at 0x7e3532 - 0x7e3535
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3532) = primary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3533) = secondary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3534) = primary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3535) = secondary;

    // 3. If modelInfo is available, update modelInfo colors at 0x65a - 0x65d
    int16_t modelIndex = *(int16_t *)(veh + 0x32);
    if (modelIndex >= 400 && modelIndex <= 611) {
        uintptr_t modelArray = (uintptr_t)slide + 0x100000000ULL + 0x7bc170;
        uintptr_t modelInfo = *(uintptr_t *)(modelArray + (uintptr_t)modelIndex * 8);
        if (modelInfo) {
            *(uint8_t *)(modelInfo + 0x65a) = primary;
            *(uint8_t *)(modelInfo + 0x65b) = secondary;
            *(uint8_t *)(modelInfo + 0x65c) = primary;
            *(uint8_t *)(modelInfo + 0x65d) = secondary;
        }
    }

    // 4. Repaint 3D model clump materials immediately via 0x231908
    uintptr_t clump = *(uintptr_t *)(veh + 0x20);
    if (clump) {
        uintptr_t repaintAddr = (uintptr_t)slide + 0x100000000ULL + 0x231908;
        void (*repaintFn)(uintptr_t) = (void(*)(uintptr_t))repaintAddr;
        if (repaintFn) {
            repaintFn(clump);
        }
    }

    return YES;
}

// CClock::SetGameClock(uint8_t hours, uint8_t minutes, uint8_t day) at 0x13bc8c
// Global offsets: Hours: 0x72df0a, Minutes: 0x72df0b, Days: 0x72df0e
static void set_game_time(uint8_t hours, uint8_t minutes) {
    if (hours > 23) hours = 23;
    if (minutes > 59) minutes = 59;

    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x13bc8c;
    void (*setClockFn)(uint8_t, uint8_t, uint8_t) = (void(*)(uint8_t, uint8_t, uint8_t))addr;
    if (setClockFn) {
        setClockFn(hours, minutes, 0);
    }

    // Direct memory backup for 100% immediate effect
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0a) = hours;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0b) = minutes;
    *(uint16_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0c) = 0;
}

static void add_game_hours(int deltaHours) {
    intptr_t slide = get_gtasa_slide();
    uint8_t *hPtr = (uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0a);
    uint8_t *mPtr = (uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0b);
    int currentH = (int)(*hPtr);
    int newH = (currentH + deltaHours) % 24;
    if (newH < 0) newH += 24;
    set_game_time((uint8_t)newH, *mPtr);
}

// HESOYAM: Direct memory write for $250k, full health, armor, and car repair (ZERO CRASHES)
static void trigger_hesoyam(void) {
    intptr_t slide = get_gtasa_slide();

    // 1. Player Info Money (+$250,000) at CWorld::Players[playerIndex].m_nMoney
    uint8_t *pIdxPtr = (uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x741e18);
    uint8_t pIndex = pIdxPtr ? *pIdxPtr : 0;
    if (pIndex > 1) pIndex = 0;
    uintptr_t playersBase = (uintptr_t)slide + 0x100000000ULL + 0x741a68;
    uintptr_t playerInfo = playersBase + (uintptr_t)pIndex * 0x1d8;
    *(int *)(playerInfo + 0xf0) += 250000;

    // 2. Direct memory write for Health & Armor (Ped)
    uintptr_t ped = get_player_ped();
    if (ped) {
        *(float *)(ped + 0x6ac) = 200.0f; // Health
        *(float *)(ped + 0x6b4) = 150.0f; // Armor
        *(float *)(ped + 0x6c4) = 200.0f; // Max Health
    }

    // 3. Repair vehicle if player is driving or spawned
    uintptr_t veh = get_current_or_last_vehicle();
    if (veh) {
        *(float *)(veh + 0x634) = 1000.0f; // Full Vehicle HP
    }
}

// God Mode (Cheksiz Jon & O'lmaslik): Bitfield 0xFF at 0x42 + GCD timer keeping health/armor pegged at max
static BOOL g_godModeEnabled = NO;
static dispatch_source_t g_godModeTimer = nil;

static void set_god_mode(BOOL enable) {
    g_godModeEnabled = enable;
    if (enable) {
        uintptr_t ped = get_player_ped();
        if (ped) {
            *(uint8_t *)(ped + 0x42) = 0xFF; // Immunity flags
            *(float *)(ped + 0x6ac) = 200.0f;
            *(float *)(ped + 0x6b4) = 150.0f;
        }
        if (!g_godModeTimer) {
            g_godModeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(g_godModeTimer, DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC, 0.05 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(g_godModeTimer, ^{
                if (g_godModeEnabled) {
                    uintptr_t p = get_player_ped();
                    if (p) {
                        *(uint8_t *)(p + 0x42) = 0xFF;
                        *(float *)(p + 0x6ac) = 200.0f;
                        *(float *)(p + 0x6b4) = 150.0f;
                    }
                    uintptr_t v = get_current_or_last_vehicle();
                    if (v) {
                        *(uint8_t *)(v + 0x42) = 0xFF;
                        *(float *)(v + 0x634) = 1000.0f;
                    }
                }
            });
            dispatch_resume(g_godModeTimer);
        }
    } else {
        if (g_godModeTimer) {
            dispatch_source_cancel(g_godModeTimer);
            g_godModeTimer = nil;
        }
        uintptr_t ped = get_player_ped();
        if (ped) {
            *(uint8_t *)(ped + 0x42) = 0x00;
        }
        uintptr_t veh = get_current_or_last_vehicle();
        if (veh) {
            *(uint8_t *)(veh + 0x42) = 0x00;
        }
    }
}

// Weather: CWeather::ForceWeatherNow(int weatherId) at 0x312b78
static void set_weather(int weatherId) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x312b78;
    void (*fn)(int) = (void(*)(int))addr;
    if (fn) {
        fn(weatherId);
    }
}

// Wanted Level: CPed::SetWantedLevel at 0x273bc8 and native cheat 0xae71c (lock 0) / 0xae750 (6 stars)
static void set_wanted_level(int stars) {
    if (stars < 0) stars = 0;
    if (stars > 6) stars = 6;

    intptr_t slide = get_gtasa_slide();
    if (stars == 0) {
        uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0xae71c;
        void (*clearCheatFn)(void) = (void(*)(void))addr;
        if (clearCheatFn) clearCheatFn();
    } else if (stars == 6) {
        uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0xae750;
        void (*maxCheatFn)(void) = (void(*)(void))addr;
        if (maxCheatFn) maxCheatFn();
    }

    uintptr_t ped = get_player_ped();
    if (ped) {
        uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x273bc8;
        void (*setWantedFn)(uintptr_t, int) = (void(*)(uintptr_t, int))addr;
        if (setWantedFn) {
            setWantedFn(ped, stars);
        }
    }
}

// Weapons Packs: 1 -> 0xacc80, 2 -> 0xacf40, 3 -> 0xad1c4
static void give_weapons_pack(int packNum) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t off = (packNum == 1) ? 0xacc80 : ((packNum == 2) ? 0xacf40 : 0xad1c4);
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + off;
    void (*fn)(void) = (void(*)(void))addr;
    if (fn) {
        fn();
    }
}

// Game Speed: CTimer::ms_fTimeScale at 0x741a30
static void set_game_speed(float speed) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x741a30;
    *(float *)addr = speed;
}

// Native Cheats: Jetpack (0xad6fc), Parachute (0xadb04), BlowUpCars (0xad66c)
static void trigger_native_cheat(uintptr_t offset) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + offset;
    void (*fn)(void) = (void(*)(void))addr;
    if (fn) {
        fn();
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
            CGFloat mw = MIN(410.0, size.width - 24.0);
            CGFloat mh = MIN(310.0, size.height - 24.0);
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
// DiroMenuModal: Full Modern Cheat Hub with 5 Categories
// -----------------------------------------------------------------------------
@interface DiroMenuModal () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subTitleLabel;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *idTextField;
@property (nonatomic, strong) UITextField *colorTextField;
@property (nonatomic, strong) UITextField *timeTextField;
@property (nonatomic, strong) UISwitch *godModeSwitch;
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
    self.titleLabel.text = @"👑 DIRO MOD MENU • GTA SAN ANDREAS";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.titleLabel.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
    [headerView addSubview:self.titleLabel];

    // Subtitle
    self.subTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 24, w - 60, 14)];
    self.subTitleLabel.text = @"100% Oflayn • Registratsiyasiz • Pro VIP Funksiyalar";
    self.subTitleLabel.font = [UIFont systemFontOfSize:10];
    self.subTitleLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    [headerView addSubview:self.subTitleLabel];

    // Close button (✕)
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w - 38, 6, 32, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleVisibility) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:closeBtn];

    // Toast status notification banner
    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 48, w - 20, 22)];
    self.toastLabel.backgroundColor = [UIColor colorWithRed:0.15 green:0.75 blue:0.35 alpha:0.25];
    self.toastLabel.layer.cornerRadius = 5;
    self.toastLabel.layer.borderColor = [UIColor colorWithRed:0.15 green:0.80 blue:0.40 alpha:0.8].CGColor;
    self.toastLabel.layer.borderWidth = 0.8;
    self.toastLabel.clipsToBounds = YES;
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    self.toastLabel.font = [UIFont boldSystemFontOfSize:11];
    self.toastLabel.textColor = [UIColor colorWithRed:0.30 green:1.00 blue:0.50 alpha:1.0];
    self.toastLabel.hidden = YES;
    [self addSubview:self.toastLabel];

    // Category segmented control (5 tabs)
    NSArray *categories = @[@"🚗 Avto", @"🎨 Rang", @"🛡️ O'yinchi", @"🔫 Qurol", @"⏰ Vaqt & Havo"];
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:categories];
    self.segmentedControl.frame = CGRectMake(8, 73, w - 16, 28);
    self.segmentedControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *)) {
        self.segmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.85];
        [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:10.5]} forState:UIControlStateSelected];
        [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:10.5]} forState:UIControlStateNormal];
    } else {
        self.segmentedControl.tintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
    }
    [self.segmentedControl addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.segmentedControl];

    // Scrollable cheat list
    CGFloat listY = 106.0;
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(8, listY, w - 16, self.bounds.size.height - listY - 8.0)];
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
        [self.colorTextField resignFirstResponder];
        [self.timeTextField resignFirstResponder];
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

    self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:2.8 target:self selector:@selector(hideToast) userInfo:nil repeats:NO];
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
    [self.colorTextField resignFirstResponder];
    [self.timeTextField resignFirstResponder];
    [self refreshCheatsList];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (textField == self.idTextField) {
        [self spawnByIdTapped];
    } else if (textField == self.colorTextField) {
        [self applyCustomColorTapped];
    } else if (textField == self.timeTextField) {
        [self applyCustomTimeTapped];
    }
    return YES;
}

// -----------------------------------------------------------------------------
// UI Builder for each category
// -----------------------------------------------------------------------------
- (void)refreshCheatsList {
    for (UIView *v in self.scrollView.subviews) {
        [v removeFromSuperview];
    }

    NSInteger cat = self.segmentedControl.selectedSegmentIndex;
    CGFloat btnW = self.scrollView.bounds.size.width;
    CGFloat curY = 0.0;

    // =========================================================================
    // Category 0: Mashinalar (Vehicle Spawner + ID Spawner)
    // =========================================================================
    if (cat == 0) {
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

        NSArray *vList = @[
            @{@"title": @"🏎️ Infernus Superkar", @"sub": @"Eng mashhur sportkar", @"vid": @(411)},
            @{@"title": @"🏎️ Bullet Superkar", @"sub": @"Tezkor Ford GT modeli", @"vid": @(541)},
            @{@"title": @"🏎️ Cheetah Superkar", @"sub": @"Klassik Ferrari modeli", @"vid": @(415)},
            @{@"title": @"🏎️ Turismo Superkar", @"sub": @"Tezkor poyga mashinasi", @"vid": @(451)},
            @{@"title": @"🚗 Sultan 4-Eshik", @"sub": @"Drift va tyuning qiroli", @"vid": @(560)},
            @{@"title": @"🚗 Elegy Sport", @"sub": @"Yaponiya drift afsonasi", @"vid": @(562)},
            @{@"title": @"🚗 Buffalo Sport", @"sub": @"Muskullar avtomobili", @"vid": @(402)},
            @{@"title": @"🏍️ NRG-500 Mototsikl", @"sub": @"O'yindagi eng tezkor mototsikl", @"vid": @(522)},
            @{@"title": @"🏍️ Sanchez Krossbayk", @"sub": @"Tog' va sakrash mototsikli", @"vid": @(468)},
            @{@"title": @"🚗 Rhino Tank", @"sub": @"Buzilmas va o't ochuvchi tank", @"vid": @(432)},
            @{@"title": @"✈️ Hydra Qiruvchi Samolyot", @"sub": @"Harbiy reaktiv qiruvchi", @"vid": @(520)},
            @{@"title": @"🚁 Hunter Vertolyot", @"sub": @"Pulemyotli harbiy vertolyot", @"vid": @(425)},
            @{@"title": @"🚙 Monster Truck", @"sub": @"Katta g'ildirakli jip", @"vid": @(444)},
            @{@"title": @"🚤 Vortex Kema / Hoverkraft", @"sub": @"Suvda ham quruqlikda yuradi", @"vid": @(539)},
            @{@"title": @"💥 Barcha Mashinalarni Portlatish", @"sub": @"Atrofdagi barcha avtolarni portlatadi", @"off": @(0xad66c), @"msg": @"💥 Barcha mashinalar portlatildi!"}
        ];

        CGFloat btnH = 38.0;
        CGFloat gap = 6.0;
        for (NSDictionary *dict in vList) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(0, curY, btnW, btnH);
            btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
            btn.layer.borderWidth = 0.8;
            btn.clipsToBounds = YES;

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, btnW - 85, 18)];
            lbl.text = dict[@"title"];
            lbl.font = [UIFont boldSystemFontOfSize:12];
            lbl.textColor = [UIColor whiteColor];
            lbl.userInteractionEnabled = NO;
            [btn addSubview:lbl];

            UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 20, btnW - 85, 14)];
            sub.text = dict[@"sub"];
            sub.font = [UIFont systemFontOfSize:9.5];
            sub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
            sub.userInteractionEnabled = NO;
            [btn addSubview:sub];

            UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btnW - 72, (btnH - 20) / 2.0, 64, 20)];
            badge.text = dict[@"vid"] ? [NSString stringWithFormat:@"ID %d", [dict[@"vid"] intValue]] : @"BOOM";
            badge.font = [UIFont boldSystemFontOfSize:10];
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

    // =========================================================================
    // Category 1: Mashina Rangi (Vehicle Color Changer)
    // =========================================================================
    if (cat == 1) {
        UIView *infoCard = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 30)];
        infoCard.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.15 alpha:1.0];
        infoCard.layer.cornerRadius = 6.0;
        infoCard.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.5].CGColor;
        infoCard.layer.borderWidth = 0.8;

        UILabel *infoLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, btnW - 16, 30)];
        infoLbl.text = @"🚗 Mashinaga o'tiring va istalgan rangni bosing:";
        infoLbl.font = [UIFont boldSystemFontOfSize:11];
        infoLbl.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [infoCard addSubview:infoLbl];
        [self.scrollView addSubview:infoCard];
        curY += 36.0;

        NSArray *colors = @[
            @{@"name": @"⬛ Qora", @"id": @(0), @"bg": [UIColor colorWithWhite:0.08 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"⬜ Oq", @"id": @(1), @"bg": [UIColor colorWithWhite:0.92 alpha:1.0], @"text": [UIColor blackColor]},
            @{@"name": @"🟥 Qizil", @"id": @(3), @"bg": [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🟦 Ko'k", @"id": @(8), @"bg": [UIColor colorWithRed:0.15 green:0.35 blue:0.85 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🟨 Oltin", @"id": @(6), @"bg": [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0], @"text": [UIColor blackColor]},
            @{@"name": @"🟩 Yashil", @"id": @(16), @"bg": [UIColor colorWithRed:0.15 green:0.75 blue:0.25 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🟪 Binafsha", @"id": @(67), @"bg": [UIColor colorWithRed:0.55 green:0.15 blue:0.85 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🌸 Pushti", @"id": @(126), @"bg": [UIColor colorWithRed:1.00 green:0.30 blue:0.70 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🔘 Kumush", @"id": @(79), @"bg": [UIColor colorWithWhite:0.70 alpha:1.0], @"text": [UIColor blackColor]},
            @{@"name": @"🟧 To'q Sariq", @"id": @(7), @"bg": [UIColor colorWithRed:1.00 green:0.45 blue:0.05 alpha:1.0], @"text": [UIColor whiteColor]},
            @{@"name": @"🔷 Moviy", @"id": @(9), @"bg": [UIColor colorWithRed:0.15 green:0.75 blue:0.95 alpha:1.0], @"text": [UIColor blackColor]},
            @{@"name": @"🟤 Bronza", @"id": @(36), @"bg": [UIColor colorWithRed:0.60 green:0.25 blue:0.15 alpha:1.0], @"text": [UIColor whiteColor]}
        ];

        CGFloat colGap = 6.0;
        int numCols = 4;
        CGFloat colBtnW = (btnW - (numCols - 1) * colGap) / (CGFloat)numCols;
        CGFloat colBtnH = 34.0;

        for (int i = 0; i < colors.count; i++) {
            NSDictionary *cDict = colors[i];
            int r = i / numCols;
            int c = i % numCols;
            CGFloat bx = c * (colBtnW + colGap);
            CGFloat by = curY + r * (colBtnH + colGap);

            UIButton *cBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            cBtn.frame = CGRectMake(bx, by, colBtnW, colBtnH);
            cBtn.backgroundColor = cDict[@"bg"];
            cBtn.layer.cornerRadius = 6.0;
            cBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
            cBtn.layer.borderWidth = 1.0;
            cBtn.clipsToBounds = YES;

            [cBtn setTitle:cDict[@"name"] forState:UIControlStateNormal];
            [cBtn setTitleColor:cDict[@"text"] forState:UIControlStateNormal];
            cBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];

            objc_setAssociatedObject(cBtn, "color_id", cDict[@"id"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [cBtn addTarget:self action:@selector(presetColorTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:cBtn];
        }

        int totalRows = (int)((colors.count + numCols - 1) / numCols);
        curY += totalRows * (colBtnH + colGap) + 8.0;

        UIView *customCard = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 76)];
        customCard.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:1.0];
        customCard.layer.cornerRadius = 8.0;
        customCard.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.6].CGColor;
        customCard.layer.borderWidth = 1.0;
        customCard.clipsToBounds = YES;

        UILabel *customTitle = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, btnW - 16, 16)];
        customTitle.text = @"🔢 Qo'lda rang ID kiritish (0 dan 127 gacha):";
        customTitle.font = [UIFont boldSystemFontOfSize:11];
        customTitle.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [customCard addSubview:customTitle];

        self.colorTextField = [[UITextField alloc] initWithFrame:CGRectMake(8, 28, btnW - 110, 38)];
        self.colorTextField.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        self.colorTextField.layer.cornerRadius = 6;
        self.colorTextField.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
        self.colorTextField.layer.borderWidth = 0.8;
        self.colorTextField.textColor = [UIColor whiteColor];
        self.colorTextField.font = [UIFont boldSystemFontOfSize:14];
        self.colorTextField.placeholder = @"Masalan: 3";
        self.colorTextField.keyboardType = UIKeyboardTypeNumberPad;
        self.colorTextField.textAlignment = NSTextAlignmentCenter;
        self.colorTextField.delegate = self;
        if (@available(iOS 13.0, *)) {
            self.colorTextField.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        [customCard addSubview:self.colorTextField];

        UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        applyBtn.frame = CGRectMake(btnW - 96, 28, 88, 38);
        applyBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        applyBtn.layer.cornerRadius = 6;
        [applyBtn setTitle:@"🎨 BO'YASH" forState:UIControlStateNormal];
        [applyBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        applyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [applyBtn addTarget:self action:@selector(applyCustomColorTapped) forControlEvents:UIControlEventTouchUpInside];
        [customCard addSubview:applyBtn];

        [self.scrollView addSubview:customCard];
        curY += 84.0;

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }

    // =========================================================================
    // Category 2: O'yinchi (Player Health, God Mode, Money, Motion)
    // =========================================================================
    if (cat == 2) {
        UIView *godCard = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 54)];
        godCard.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.16 alpha:1.0];
        godCard.layer.cornerRadius = 8.0;
        godCard.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.7].CGColor;
        godCard.layer.borderWidth = 1.0;
        godCard.clipsToBounds = YES;

        UILabel *godTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, btnW - 80, 18)];
        godTitle.text = @"👑 Cheksiz Jon & O'lmaslik (God Mode)";
        godTitle.font = [UIFont boldSystemFontOfSize:12];
        godTitle.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [godCard addSubview:godTitle];

        UILabel *godSub = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, btnW - 80, 16)];
        godSub.text = @"CJ va minib turgan mashinasi mutlaqo o'lmas bo'ladi";
        godSub.font = [UIFont systemFontOfSize:9.5];
        godSub.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
        [godCard addSubview:godSub];

        self.godModeSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(btnW - 62, 11, 51, 31)];
        self.godModeSwitch.on = g_godModeEnabled;
        self.godModeSwitch.onTintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        [self.godModeSwitch addTarget:self action:@selector(godModeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        [godCard addSubview:self.godModeSwitch];

        [self.scrollView addSubview:godCard];
        curY += 60.0;

        NSArray *pCheats = @[
            @{
                @"title": @"💰 HESOYAM: $250,000 + 100% Jon + Bronya + Avto",
                @"sub": @"Darhol pul, to'liq salomatlik beradi va avtoni tuzatadi",
                @"badge": @"BERISH",
                @"action": @"hesoyam"
            },
            @{
                @"title": @"🚀 Jetpack Chiqarish (Uchish Ryukzaki)",
                @"sub": @"CJ orqasiga havoda uchish reaktiv ryukzaki beradi",
                @"badge": @"UCHISH",
                @"off": @(0xad6fc),
                @"msg": @"✅ Jetpack chiqarildi!"
            },
            @{
                @"title": @"🪂 Parashyut Berish",
                @"sub": @"Balandlikdan xavfsiz sakrash parashyuti",
                @"badge": @"BERISH",
                @"off": @(0xadb04),
                @"msg": @"✅ Parashyut berildi!"
            },
            @{
                @"title": @"⚡ Tez Harakat (Fast Motion 4x)",
                @"sub": @"O'yin jarayonini 4 baravar tezlashtiradi",
                @"badge": @"4X TEZ",
                @"speed": @(4.0f),
                @"msg": @"⚡ O'yin tezligi 4 baravar oshirildi!"
            },
            @{
                @"title": @"⏳ Sekin Harakat (Slow Motion 0.25x)",
                @"sub": @"O'yin jarayonini 4 baravar sekinlashtiradi",
                @"badge": @"0.25X",
                @"speed": @(0.25f),
                @"msg": @"⏳ Sekin harakat yoqildi!"
            },
            @{
                @"title": @"🔄 Standart Tezlik (Normal Motion 1x)",
                @"sub": @"O'yin tezligini normal holatiga qaytaradi",
                @"badge": @"1.0X",
                @"speed": @(1.0f),
                @"msg": @"🔄 O'yin tezligi normal holatga keltirildi!"
            }
        ];

        CGFloat btnH = 40.0;
        CGFloat gap = 6.0;
        for (NSDictionary *dict in pCheats) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(0, curY, btnW, btnH);
            btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
            btn.layer.borderWidth = 0.8;
            btn.clipsToBounds = YES;

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, btnW - 85, 18)];
            lbl.text = dict[@"title"];
            lbl.font = [UIFont boldSystemFontOfSize:12];
            lbl.textColor = [UIColor whiteColor];
            lbl.userInteractionEnabled = NO;
            [btn addSubview:lbl];

            UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 22, btnW - 85, 14)];
            sub.text = dict[@"sub"];
            sub.font = [UIFont systemFontOfSize:9.5];
            sub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
            sub.userInteractionEnabled = NO;
            [btn addSubview:sub];

            UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btnW - 74, (btnH - 20) / 2.0, 66, 20)];
            badge.text = dict[@"badge"];
            badge.font = [UIFont boldSystemFontOfSize:10];
            badge.textColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.15];
            badge.layer.cornerRadius = 4;
            badge.clipsToBounds = YES;
            badge.userInteractionEnabled = NO;
            [btn addSubview:badge];

            objc_setAssociatedObject(btn, "player_cheat", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(playerCheatTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
            curY += btnH + gap;
        }

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }

    // =========================================================================
    // Category 3: Qurollar (Weapons Packs 1, 2, 3)
    // =========================================================================
    if (cat == 3) {
        NSArray *wPacks = @[
            @{
                @"title": @"🔫 1-To'plam (Ko'cha qurollari)",
                @"sub": @"Kastet, Bita, 9mm, Shotgun, Micro Uzi, AK-47, Vintovka, Bazuka, Molotov",
                @"badge": @"1-TO'PLAM",
                @"pack": @(1)
            },
            @{
                @"title": @"💣 2-To'plam (Professional qurollar)",
                @"sub": @"Pichoq, Desert Eagle, Qirqma Shotgun, TEC-9, M4, Snayper, O't sochgich, Granata",
                @"badge": @"2-TO'PLAM",
                @"pack": @(2)
            },
            @{
                @"title": @"🚀 3-To'plam (Maxsus Kuchlar qurollari)",
                @"sub": @"Benzopila, O'chirgichli Pistol, SPAS-12, MP5, M4, Minigun, C4 Portlovchi Paket",
                @"badge": @"3-TO'PLAM",
                @"pack": @(3)
            }
        ];

        CGFloat btnH = 50.0;
        CGFloat gap = 8.0;
        for (NSDictionary *dict in wPacks) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(0, curY, btnW, btnH);
            btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.5].CGColor;
            btn.layer.borderWidth = 1.0;
            btn.clipsToBounds = YES;

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, btnW - 90, 18)];
            lbl.text = dict[@"title"];
            lbl.font = [UIFont boldSystemFontOfSize:13];
            lbl.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
            lbl.userInteractionEnabled = NO;
            [btn addSubview:lbl];

            UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 26, btnW - 90, 18)];
            sub.text = dict[@"sub"];
            sub.font = [UIFont systemFontOfSize:9.5];
            sub.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
            sub.userInteractionEnabled = NO;
            [btn addSubview:sub];

            UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btnW - 84, (btnH - 24) / 2.0, 76, 24)];
            badge.text = dict[@"badge"];
            badge.font = [UIFont boldSystemFontOfSize:10];
            badge.textColor = [UIColor blackColor];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
            badge.layer.cornerRadius = 5;
            badge.clipsToBounds = YES;
            badge.userInteractionEnabled = NO;
            [btn addSubview:badge];

            objc_setAssociatedObject(btn, "weapon_info", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(weaponPackTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
            curY += btnH + gap;
        }

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }

    // =========================================================================
    // Category 4: Vaqt & Havo (Clock, Weather & Wanted Level)
    // =========================================================================
    if (cat == 4) {
        // --- Section 1: Soat / Vaqtni o'zgartirish ---
        UILabel *tHead = [[UILabel alloc] initWithFrame:CGRectMake(4, curY, btnW - 8, 16)];
        tHead.text = @"⏰ Soat / Vaqtni o'zgartirish:";
        tHead.font = [UIFont boldSystemFontOfSize:11];
        tHead.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [self.scrollView addSubview:tHead];
        curY += 20.0;

        // 4 Preset Time Buttons
        NSArray *timePresets = @[
            @{@"name": @"🌅 Tong (06:00)", @"h": @(6), @"m": @(0)},
            @{@"name": @"☀️ Kunduz (12:00)", @"h": @(12), @"m": @(0)},
            @{@"name": @"🌇 Oqshom (20:00)", @"h": @(20), @"m": @(0)},
            @{@"name": @"🌙 Tun (00:00)", @"h": @(0), @"m": @(0)}
        ];

        CGFloat tGap = 6.0;
        int tCols = 2;
        CGFloat tBtnW = (btnW - (tCols - 1) * tGap) / (CGFloat)tCols;
        CGFloat tBtnH = 32.0;

        for (int i = 0; i < timePresets.count; i++) {
            NSDictionary *tDict = timePresets[i];
            int r = i / tCols;
            int c = i % tCols;
            CGFloat bx = c * (tBtnW + tGap);
            CGFloat by = curY + r * (tBtnH + tGap);

            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(bx, by, tBtnW, tBtnH);
            btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.19 alpha:1.0];
            btn.layer.cornerRadius = 6.0;
            btn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.4].CGColor;
            btn.layer.borderWidth = 0.8;
            [btn setTitle:tDict[@"name"] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];

            objc_setAssociatedObject(btn, "time_dict", tDict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(presetTimeTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
        }
        curY += 2 * (tBtnH + tGap) + 4.0;

        // 2 Shift buttons: -1 hour and +1 hour
        CGFloat sBtnW = (btnW - tGap) / 2.0;
        UIButton *minusHourBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        minusHourBtn.frame = CGRectMake(0, curY, sBtnW, 30);
        minusHourBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        minusHourBtn.layer.cornerRadius = 6.0;
        [minusHourBtn setTitle:@"⏪ -1 Soat Orqaga" forState:UIControlStateNormal];
        [minusHourBtn setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
        minusHourBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [minusHourBtn addTarget:self action:@selector(minusHourTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:minusHourBtn];

        UIButton *plusHourBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        plusHourBtn.frame = CGRectMake(sBtnW + tGap, curY, sBtnW, 30);
        plusHourBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        plusHourBtn.layer.cornerRadius = 6.0;
        [plusHourBtn setTitle:@"⏩ +1 Soat Oldinga" forState:UIControlStateNormal];
        [plusHourBtn setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
        plusHourBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [plusHourBtn addTarget:self action:@selector(plusHourTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:plusHourBtn];
        curY += 36.0;

        // Custom Hour Input Card
        UIView *timeCard = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 64)];
        timeCard.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:1.0];
        timeCard.layer.cornerRadius = 7.0;
        timeCard.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
        timeCard.layer.borderWidth = 0.8;

        UILabel *timePrompt = [[UILabel alloc] initWithFrame:CGRectMake(8, 5, btnW - 16, 14)];
        timePrompt.text = @"🔢 Qo'lda soat kiritish (0 dan 23 gacha):";
        timePrompt.font = [UIFont boldSystemFontOfSize:10.5];
        timePrompt.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
        [timeCard addSubview:timePrompt];

        self.timeTextField = [[UITextField alloc] initWithFrame:CGRectMake(8, 24, btnW - 120, 32)];
        self.timeTextField.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        self.timeTextField.layer.cornerRadius = 5;
        self.timeTextField.textColor = [UIColor whiteColor];
        self.timeTextField.font = [UIFont boldSystemFontOfSize:13];
        self.timeTextField.placeholder = @"Masalan: 18";
        self.timeTextField.keyboardType = UIKeyboardTypeNumberPad;
        self.timeTextField.textAlignment = NSTextAlignmentCenter;
        self.timeTextField.delegate = self;
        if (@available(iOS 13.0, *)) {
            self.timeTextField.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        [timeCard addSubview:self.timeTextField];

        UIButton *applyTimeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        applyTimeBtn.frame = CGRectMake(btnW - 106, 24, 98, 32);
        applyTimeBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        applyTimeBtn.layer.cornerRadius = 5;
        [applyTimeBtn setTitle:@"⏰ O'RNATISH" forState:UIControlStateNormal];
        [applyTimeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        applyTimeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [applyTimeBtn addTarget:self action:@selector(applyCustomTimeTapped) forControlEvents:UIControlEventTouchUpInside];
        [timeCard addSubview:applyTimeBtn];

        [self.scrollView addSubview:timeCard];
        curY += 72.0;

        // --- Section 2: Ob-havo ---
        UILabel *wHead = [[UILabel alloc] initWithFrame:CGRectMake(4, curY, btnW - 8, 16)];
        wHead.text = @"🌦️ Ob-havoni o'zgartirish:";
        wHead.font = [UIFont boldSystemFontOfSize:11];
        wHead.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [self.scrollView addSubview:wHead];
        curY += 20.0;

        NSArray *weathers = @[
            @{@"name": @"☀️ Quyoshli", @"id": @(0)},
            @{@"name": @"⛅ Ochiq Havo", @"id": @(1)},
            @{@"name": @"☁️ Bulutli", @"id": @(4)},
            @{@"name": @"🌧️ Yomg'ir", @"id": @(9)},
            @{@"name": @"🌫️ Tuman", @"id": @(8)},
            @{@"name": @"🌪️ Qum Bo'roni", @"id": @(16)}
        ];

        CGFloat wGap = 6.0;
        int wCols = 3;
        CGFloat wBtnW = (btnW - (wCols - 1) * wGap) / (CGFloat)wCols;
        CGFloat wBtnH = 32.0;

        for (int i = 0; i < weathers.count; i++) {
            NSDictionary *wDict = weathers[i];
            int r = i / wCols;
            int c = i % wCols;
            CGFloat bx = c * (wBtnW + wGap);
            CGFloat by = curY + r * (wBtnH + wGap);

            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(bx, by, wBtnW, wBtnH);
            btn.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.18 alpha:1.0];
            btn.layer.cornerRadius = 6.0;
            btn.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
            btn.layer.borderWidth = 0.8;
            [btn setTitle:wDict[@"name"] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];

            objc_setAssociatedObject(btn, "weather_id", wDict[@"id"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(weatherButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
        }
        curY += 2 * (wBtnH + wGap) + 12.0;

        // --- Section 3: Politsiya Qidiruvi (Wanted Level) ---
        UILabel *qHead = [[UILabel alloc] initWithFrame:CGRectMake(4, curY, btnW - 8, 16)];
        qHead.text = @"🚨 Politsiya Qidiruv Darajasi (Wanted Level):";
        qHead.font = [UIFont boldSystemFontOfSize:11];
        qHead.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [self.scrollView addSubview:qHead];
        curY += 20.0;

        NSArray *wantedCheats = @[
            @{
                @"title": @"🚫 Qidiruvni Butunlay Yo'qotish (0 Yulduz)",
                @"sub": @"Politsiya va qidiruvni butunlay to'xtatadi",
                @"badge": @"0 YULDUZ",
                @"stars": @(0)
            },
            @{
                @"title": @"⭐ Qidiruvni Pasaytirish (-1 Yulduz)",
                @"sub": @"Politsiya qidiruvini bir yulduzga kamaytiradi",
                @"badge": @"-1 YULDUZ",
                @"off": @(0xad4b8),
                @"msg": @"✅ Qidiruv 1 darajaga kamaytirildi!"
            },
            @{
                @"title": @"🚨 Qidiruvni Oshirish (+1 Yulduz)",
                @"sub": @"Politsiya qidiruvini bir yulduzga ko'taradi",
                @"badge": @"+1 YULDUZ",
                @"off": @(0xad488),
                @"msg": @"✅ Qidiruv 1 darajaga oshirildi!"
            },
            @{
                @"title": @"⭐️⭐️⭐️⭐️⭐️⭐️ Maksimal 6 Yulduz Qidiruv",
                @"sub": @"Tanklar, Armiya va Maxsus Kuchlarni chaqiradi",
                @"badge": @"6 YULDUZ",
                @"stars": @(6)
            }
        ];

        CGFloat qBtnH = 38.0;
        CGFloat qGap = 6.0;
        for (NSDictionary *dict in wantedCheats) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(0, curY, btnW, qBtnH);
            btn.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:0.95];
            btn.layer.cornerRadius = 8.0;
            btn.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
            btn.layer.borderWidth = 0.8;
            btn.clipsToBounds = YES;

            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, btnW - 85, 18)];
            lbl.text = dict[@"title"];
            lbl.font = [UIFont boldSystemFontOfSize:11.5];
            lbl.textColor = [UIColor whiteColor];
            lbl.userInteractionEnabled = NO;
            [btn addSubview:lbl];

            UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(10, 20, btnW - 85, 14)];
            sub.text = dict[@"sub"];
            sub.font = [UIFont systemFontOfSize:9.5];
            sub.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
            sub.userInteractionEnabled = NO;
            [btn addSubview:sub];

            UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btnW - 74, (qBtnH - 20) / 2.0, 66, 20)];
            badge.text = dict[@"badge"];
            badge.font = [UIFont boldSystemFontOfSize:9.5];
            badge.textColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.15];
            badge.layer.cornerRadius = 4;
            badge.clipsToBounds = YES;
            badge.userInteractionEnabled = NO;
            [btn addSubview:badge];

            objc_setAssociatedObject(btn, "wanted_info", dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [btn addTarget:self action:@selector(wantedCheatTapped:) forControlEvents:UIControlEventTouchUpInside];

            [self.scrollView addSubview:btn];
            curY += qBtnH + qGap;
        }

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }
}

// -----------------------------------------------------------------------------
// Action Handlers
// -----------------------------------------------------------------------------
- (void)hapticImpact:(int)style {
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackStyle st = (style == 1) ? UIImpactFeedbackStyleHeavy : UIImpactFeedbackStyleMedium;
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:st];
        [gen prepare];
        [gen impactOccurred];
    }
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

    [self hapticImpact:1];
    trigger_vehicle_cheat(vid);
    NSString *vName = get_vehicle_name(vid);
    [self showToast:[NSString stringWithFormat:@"✅ Paydo bo'ldi: ID %d (%@)", vid, vName]];
}

- (void)vehicleListButtonTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "cheat_info");
    if (!dict) return;

    [self hapticImpact:2];

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

- (void)presetColorTapped:(UIButton *)sender {
    NSNumber *num = objc_getAssociatedObject(sender, "color_id");
    if (!num) return;

    int cid = [num intValue];
    [self hapticImpact:2];

    BOOL ok = change_vehicle_color((uint8_t)cid, (uint8_t)cid);
    if (ok) {
        [self showToast:[NSString stringWithFormat:@"✅ Mashina rangi o'zgartirildi! (ID: %d)", cid]];
    } else {
        [self showToast:@"⚠️ Avval mashinaga o'tiring yoki mashina chiqaring!"];
    }
}

- (void)applyCustomColorTapped {
    [self.colorTextField resignFirstResponder];
    NSString *txt = [self.colorTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (txt.length == 0) {
        [self showToast:@"⚠️ Rang ID sini kiriting! (0 - 127)"];
        return;
    }

    int cid = [txt intValue];
    if (cid < 0 || cid > 127) {
        [self showToast:@"⚠️ Rang ID si 0 dan 127 oralig'ida bo'lishi kerak!"];
        return;
    }

    [self hapticImpact:2];
    BOOL ok = change_vehicle_color((uint8_t)cid, (uint8_t)cid);
    if (ok) {
        [self showToast:[NSString stringWithFormat:@"✅ Mashina rangi o'zgartirildi! (ID: %d)", cid]];
    } else {
        [self showToast:@"⚠️ Avval mashinaga o'tiring yoki mashina chiqaring!"];
    }
}

- (void)presetTimeTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "time_dict");
    if (!dict) return;

    [self hapticImpact:2];
    int h = [dict[@"h"] intValue];
    int m = [dict[@"m"] intValue];
    set_game_time((uint8_t)h, (uint8_t)m);
    [self showToast:[NSString stringWithFormat:@"⏰ Soat %02d:%02d ga o'rnatildi!", h, m]];
}

- (void)minusHourTapped {
    [self hapticImpact:2];
    add_game_hours(-1);
    intptr_t slide = get_gtasa_slide();
    uint8_t currentH = *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0a);
    [self showToast:[NSString stringWithFormat:@"⏰ 1 soat orqaga: Hozir %02d:00", currentH]];
}

- (void)plusHourTapped {
    [self hapticImpact:2];
    add_game_hours(1);
    intptr_t slide = get_gtasa_slide();
    uint8_t currentH = *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x72df0a);
    [self showToast:[NSString stringWithFormat:@"⏰ 1 soat oldinga: Hozir %02d:00", currentH]];
}

- (void)applyCustomTimeTapped {
    [self.timeTextField resignFirstResponder];
    NSString *txt = [self.timeTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (txt.length == 0) {
        [self showToast:@"⚠️ Soatni kiriting! (0 - 23)"];
        return;
    }

    int h = [txt intValue];
    if (h < 0 || h > 23) {
        [self showToast:@"⚠️ Soat 0 dan 23 oralig'ida bo'lishi kerak!"];
        return;
    }

    [self hapticImpact:2];
    set_game_time((uint8_t)h, 0);
    [self showToast:[NSString stringWithFormat:@"⏰ Soat %02d:00 ga o'rnatildi!", h]];
}

- (void)godModeSwitchChanged:(UISwitch *)sender {
    [self hapticImpact:1];
    set_god_mode(sender.isOn);
    if (sender.isOn) {
        [self showToast:@"✅ God Mode (O'lmaslik) yoqildi! CJ va Avto 100% o'lmas!"];
    } else {
        [self showToast:@"❌ God Mode o'chirildi."];
    }
}

- (void)playerCheatTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "player_cheat");
    if (!dict) return;

    [self hapticImpact:2];

    if ([dict[@"action"] isEqualToString:@"hesoyam"]) {
        trigger_hesoyam();
        [self showToast:@"✅ $250,000, 100% Jon, Bronya berildi va Mashina tuzatildi!"];
    } else if (dict[@"speed"]) {
        float spd = [dict[@"speed"] floatValue];
        set_game_speed(spd);
        [self showToast:dict[@"msg"]];
    } else if (dict[@"off"]) {
        uintptr_t off = [dict[@"off"] unsignedIntegerValue];
        trigger_native_cheat(off);
        [self showToast:dict[@"msg"]];
    }
}

- (void)weaponPackTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "weapon_info");
    if (!dict) return;

    [self hapticImpact:1];
    int p = [dict[@"pack"] intValue];
    give_weapons_pack(p);
    [self showToast:[NSString stringWithFormat:@"✅ %d-To'plam qurollari berildi! (Ekranning o'ng tepasidagi belgi orqali almashtiring)", p]];
}

- (void)weatherButtonTapped:(UIButton *)sender {
    NSNumber *wNum = objc_getAssociatedObject(sender, "weather_id");
    if (!wNum) return;

    [self hapticImpact:2];
    int wid = [wNum intValue];
    set_weather(wid);
    [self showToast:[NSString stringWithFormat:@"✅ Ob-havo o'zgartirildi! (%@)", sender.titleLabel.text]];
}

- (void)wantedCheatTapped:(UIButton *)sender {
    NSDictionary *dict = objc_getAssociatedObject(sender, "wanted_info");
    if (!dict) return;

    [self hapticImpact:2];

    if (dict[@"stars"]) {
        int stars = [dict[@"stars"] intValue];
        set_wanted_level(stars);
        if (stars == 0) {
            [self showToast:@"✅ Barcha qidiruvlar o'chirildi! (0 Yulduz)"];
        } else {
            [self showToast:[NSString stringWithFormat:@"🚨 %d Yulduz qidiruv darajasi berildi!", stars]];
        }
    } else if (dict[@"off"]) {
        uintptr_t off = [dict[@"off"] unsignedIntegerValue];
        trigger_native_cheat(off);
        [self showToast:dict[@"msg"]];
    }
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

        CGFloat mw = MIN(410.0, sz.width - 24.0);
        CGFloat mh = MIN(310.0, sz.height - 24.0);
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
