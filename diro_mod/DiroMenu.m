#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

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

@class DiroDroneOverlayView;
static DiroWindow *g_diroWindow = nil;
static DiroFloatingButton *g_floatingButton = nil;
static DiroMenuModal *g_menuModal = nil;
static DiroDroneOverlayView *g_droneOverlay = nil;

static void trigger_native_cheat(uintptr_t offset);

// -----------------------------------------------------------------------------
// ASLR Slide & Engine Pointers
// -----------------------------------------------------------------------------
static intptr_t get_gtasa_slide(void) {
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

// Helper to get entity coordinates (CPed or CVehicle)
static void get_entity_position(uintptr_t entity, float *outX, float *outY, float *outZ) {
    if (!entity) return;
    uintptr_t m = *(uintptr_t *)(entity + 0x18);
    float *pos = (float *)(m ? (m + 0x30) : (entity + 0x8));
    if (outX) *outX = pos[0];
    if (outY) *outY = pos[1];
    if (outZ) *outZ = pos[2];
}

// Robust target vehicle detection:
// 1. If player is inside a vehicle (ped + 0x708), return it immediately.
// 2. If player is on foot, scan CPools::ms_pVehiclePool (0x734fe0) and find the closest active vehicle within 60 meters.
// 3. Fall back to g_lastSpawnedVehicle.
static uintptr_t get_target_vehicle(void) {
    uintptr_t ped = get_player_ped();
    if (ped) {
        uintptr_t v = *(uintptr_t *)(ped + 0x708);
        if (v) return v;
    }

    intptr_t slide = get_gtasa_slide();
    uintptr_t poolPtr = (uintptr_t)slide + 0x100000000ULL + 0x734fe0;
    uintptr_t pool = *(uintptr_t *)poolPtr;

    if (pool && ped) {
        uintptr_t objects = *(uintptr_t *)(pool + 0);
        uint8_t *byteMap = *(uint8_t **)(pool + 8);
        int32_t size = *(int32_t *)(pool + 0x10);

        if (objects && byteMap && size > 0) {
            float px = 0.0f, py = 0.0f, pz = 0.0f;
            get_entity_position(ped, &px, &py, &pz);

            uintptr_t closestVeh = 0;
            float minDistanceSq = 60.0f * 60.0f; // within 60 meters

            for (int32_t i = 0; i < size; i++) {
                // In CPool, slot is active if (byteMap[i] & 0x80) == 0
                if ((byteMap[i] & 0x80) != 0) continue;

                uintptr_t veh = objects + (uintptr_t)i * 3176ULL; // sizeof(CVehicle) = 3176 (0xc68)

                float vx = 0.0f, vy = 0.0f, vz = 0.0f;
                get_entity_position(veh, &vx, &vy, &vz);

                float dx = vx - px;
                float dy = vy - py;
                float dz = vz - pz;
                float distSq = dx * dx + dy * dy + dz * dz;

                if (distSq < minDistanceSq) {
                    minDistanceSq = distSq;
                    closestVeh = veh;
                }
            }

            if (closestVeh) {
                return closestVeh;
            }
        }
    }

    if (g_lastSpawnedVehicle) {
        return g_lastSpawnedVehicle;
    }

    return 0;
}

static uintptr_t get_player_vehicle(void) {
    uintptr_t ped = get_player_ped();
    if (ped) {
        uintptr_t v = *(uintptr_t *)(ped + 0x708);
        if (v) return v;
    }
    return 0;
}

static uintptr_t get_current_or_last_vehicle(void) {
    return get_target_vehicle();
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

    // Refresh closest vehicle immediately
    uintptr_t target = get_target_vehicle();
    if (target) {
        g_lastSpawnedVehicle = target;
    }
}

// Vehicle Color Changer:
// Sets vehicle color slots 0x574..0x577, sets bit 2 of 0x56f (preventing SetupRender reset),
// clears remap/paintjob (0x734 and SetRemap 0x408b20), and updates CVehicleModelInfo::SetColour at 0x231a34.
// CVehicle::SetupRender (0x408e00) will automatically render the new colors every frame.
static BOOL change_vehicle_color(uint8_t primary, uint8_t secondary) {
    uintptr_t veh = get_target_vehicle();
    if (!veh) return NO;

    intptr_t slide = get_gtasa_slide();

    // 1. Vehicle color slots
    *(uint8_t *)(veh + 0x574) = primary;
    *(uint8_t *)(veh + 0x575) = secondary;
    *(uint8_t *)(veh + 0x576) = primary;
    *(uint8_t *)(veh + 0x577) = secondary;

    // Direct backup at legacy and alternative offsets
    *(uint8_t *)(veh + 0x17d) = primary;
    *(uint8_t *)(veh + 0x17e) = secondary;
    *(uint8_t *)(veh + 0x704) = primary;
    *(uint8_t *)(veh + 0x705) = secondary;
    *(uint8_t *)(veh + 0x706) = primary;
    *(uint8_t *)(veh + 0x707) = secondary;

    // 2. Prevent SetupRender from forcing white (1) on color 0
    *(uint8_t *)(veh + 0x56f) |= 0x04;

    // 3. Clear any paintjob / remap texture that overrides the body color
    *(uint32_t *)(veh + 0x734) = 0;
    uintptr_t setRemapAddr = (uintptr_t)slide + 0x100000000ULL + 0x408b20;
    void (*setRemapFn)(uintptr_t, int) = (void(*)(uintptr_t, int))setRemapAddr;
    if (setRemapFn) {
        setRemapFn(veh, -1);
    }

    // 4. Update modelInfo colors and call CVehicleModelInfo::SetColour
    int16_t modelIndex = *(int16_t *)(veh + 0x32);
    if (modelIndex >= 400 && modelIndex <= 611) {
        uintptr_t modelArray = (uintptr_t)slide + 0x100000000ULL + 0x7bc170;
        uintptr_t modelInfo = *(uintptr_t *)(modelArray + (uintptr_t)modelIndex * 8);
        if (modelInfo) {
            *(uint8_t *)(modelInfo + 0x65a) = primary;
            *(uint8_t *)(modelInfo + 0x65b) = secondary;
            *(uint8_t *)(modelInfo + 0x65c) = primary;
            *(uint8_t *)(modelInfo + 0x65d) = secondary;

            uintptr_t setColourAddr = (uintptr_t)slide + 0x100000000ULL + 0x231a34;
            void (*setColourFn)(uintptr_t, uint8_t, uint8_t, uint8_t, uint8_t) =
                (void(*)(uintptr_t, uint8_t, uint8_t, uint8_t, uint8_t))setColourAddr;
            if (setColourFn) {
                setColourFn(modelInfo, primary, secondary, primary, secondary);
            }
        }
    }

    // 5. Update global palette indices at 0x7e3532 - 0x7e3535
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3532) = primary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3533) = secondary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3534) = primary;
    *(uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x7e3535) = secondary;

    return YES;
}

// -----------------------------------------------------------------------------
// Drone & Camera Engine Functions
// -----------------------------------------------------------------------------
static uintptr_t get_the_camera(void) {
    intptr_t slide = get_gtasa_slide();
    return (uintptr_t)slide + 0x100000000ULL + 0x72cf08;
}

static void camera_take_control(const float target[3], int16_t switchType) {
    uintptr_t cam = get_the_camera();
    if (!cam) return;
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x13aa78;
    void (*fn)(uintptr_t, const float *, int16_t, int32_t) =
        (void(*)(uintptr_t, const float *, int16_t, int32_t))addr;
    if (fn && target) {
        fn(cam, target, switchType, 1);
    }

    // Direct memory flags to lock camera under script/drone control
    *(int32_t *)(cam + 0xb4) = 1;           // whoTakesControl = 1 (SCRIPT)
    *(int16_t *)(cam + 0xc64) = 15;         // MODE 15 (Point at Target)
    *(uint16_t *)(cam + 0x31) = 0x100;
    *(uint8_t *)(cam + 0x36) = 1;           // Request cam switch
    *(uint8_t *)(cam + 0x38) = 1;           // Trigger script cam update in CCamera::Process
    *(int16_t *)(cam + 0xc68) = switchType; // 2 = JUMP_CUT
    if (target) {
        *(float *)(cam + 0x83c) = target[0];
        *(float *)(cam + 0x840) = target[1];
        *(float *)(cam + 0x844) = target[2];
    }
}

static void camera_set_fixed_pos(const float pos[3], const float target[3]) {
    uintptr_t cam = get_the_camera();
    if (!cam) return;
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x133618;
    void (*fn)(uintptr_t, const float *, const float *) =
        (void(*)(uintptr_t, const float *, const float *))addr;
    if (fn) {
        fn(cam, pos, target);
    }

    // Direct script buffer assignments
    *(float *)(cam + 0x83c) = target[0];
    *(float *)(cam + 0x840) = target[1];
    *(float *)(cam + 0x844) = target[2];
    *(float *)(cam + 0x848) = pos[0];
    *(float *)(cam + 0x84c) = pos[1];
    *(float *)(cam + 0x850) = pos[2];
    *(float *)(cam + 0x854) = target[0];
    *(float *)(cam + 0x858) = target[1];
    *(float *)(cam + 0x85c) = target[2];
    *(uint8_t *)(cam + 0x54) = 0;
}

static void camera_set_fov(float fov) {
    uintptr_t cam = get_the_camera();
    if (!cam) return;
    uint8_t activeIdx = *(uint8_t *)(cam + 0x5f);
    if (activeIdx > 2) activeIdx = 0;
    uintptr_t activeCam = cam + (uintptr_t)activeIdx * 0x228;
    *(float *)(activeCam + 0x8c) = fov;
    *(float *)(activeCam + 0x90) = fov;
    *(float *)(activeCam + 0x94) = fov;
    *(float *)(cam + 0xd0) = fov;
}

static void camera_restore(void) {
    uintptr_t cam = get_the_camera();
    if (!cam) return;
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x133488; // CCamera::RestoreWithJumpCut (Opcode 015A)
    void (*fn)(uintptr_t) = (void(*)(uintptr_t))addr;
    if (fn) {
        fn(cam);
    }
    *(int32_t *)(cam + 0xb4) = 0;
    *(uint16_t *)(cam + 0x31) = 0;
    *(uint8_t *)(cam + 0x36) = 1;
    *(uint8_t *)(cam + 0x38) = 0;
}

static UIView *get_game_view(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) {
        if (w != g_diroWindow && ![w isKindOfClass:NSClassFromString(@"DiroWindow")]) {
            NSString *cls = NSStringFromClass([w class]);
            if ([cls containsString:@"ButtonWindow"] || 
                [cls containsString:@"IGWindow"] || 
                [cls containsString:@"IGFloating"] || 
                [cls containsString:@"iOSGods"]) {
                continue;
            }
            UIViewController *rvc = w.rootViewController;
            if (rvc && rvc.view) {
                return rvc.view;
            }
            if (w.subviews.count > 0) {
                return w.subviews[0];
            }
            return w;
        }
    }
    return nil;
}

static void set_game_rotation(float angle) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *gv = get_game_view();
        if (gv) {
            if (fabsf(angle) < 0.001f) {
                gv.transform = CGAffineTransformIdentity;
            } else {
                gv.transform = CGAffineTransformMakeRotation(angle);
            }
        }
    });
}

static void set_game_hud_visible(BOOL visible) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t hudFlag = (uintptr_t)slide + 0x100000000ULL + 0x4e333c;
    *(uint8_t *)hudFlag = visible ? 1 : 0;

    uintptr_t cam = get_the_camera();
    if (cam) {
        *(uint16_t *)(cam + 0x42) = visible ? 0x100 : 0;
    }
}

static void set_game_frozen(BOOL freeze) {
    intptr_t slide = get_gtasa_slide();
    uintptr_t addr = (uintptr_t)slide + 0x100000000ULL + 0x741a30;
    if (freeze) {
        *(float *)addr = 0.00001f;
    } else {
        *(float *)addr = 1.0f;
    }
}

static void teleport_player_to_coords(float x, float y, float z) {
    uintptr_t ped = get_player_ped();
    if (!ped) return;
    uintptr_t target = ped;
    uintptr_t veh = *(uintptr_t *)(ped + 0x708);
    if (veh) {
        target = veh;
    }

    uintptr_t m = *(uintptr_t *)(target + 0x18);
    if (m) {
        *(float *)(m + 0x30) = x;
        *(float *)(m + 0x34) = y;
        *(float *)(m + 0x38) = z;
    }
    *(float *)(target + 0x8) = x;
    *(float *)(target + 0xc) = y;
    *(float *)(target + 0x10) = z;

    *(float *)(target + 0x44) = 0.0f;
    *(float *)(target + 0x48) = 0.0f;
    *(float *)(target + 0x4c) = 0.0f;
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

// HESOYAM: Official native cheat 0xad3d4 + $250k cash (100% stable, zero crashes)
static void trigger_hesoyam(void) {
    // 1. Call GTA SA engine native CCheat::MoneyArmourHealthCheat() at 0xad3d4
    trigger_native_cheat(0xad3d4);

    // 2. Also ensure player gets +$250,000 cash directly into player info
    intptr_t slide = get_gtasa_slide();
    uint8_t *pIdxPtr = (uint8_t *)((uintptr_t)slide + 0x100000000ULL + 0x741e18);
    uint8_t pIndex = pIdxPtr ? *pIdxPtr : 0;
    if (pIndex > 1) pIndex = 0;
    uintptr_t playersBase = (uintptr_t)slide + 0x100000000ULL + 0x741a68;
    uintptr_t playerInfo = playersBase + (uintptr_t)pIndex * 0x1d8;
    *(int *)(playerInfo + 0xf0) += 250000;
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
        self.windowLevel = UIWindowLevelAlert + 1000.0;
        self.userInteractionEnabled = YES;
    }
    return self;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene API_AVAILABLE(ios(13.0)) {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.windowLevel = UIWindowLevelAlert + 1000.0;
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
// DiroVirtualJoystickView: Smooth Glowing Joystick Pad (Visual Only)
// -----------------------------------------------------------------------------
@interface DiroVirtualJoystickView : UIView
@property (nonatomic, strong) UIView *baseView;
@property (nonatomic, strong) UIView *knobView;
- (void)setKnobOffset:(CGPoint)offset;
- (void)resetKnob;
@end

@implementation DiroVirtualJoystickView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;

        CGFloat baseSize = frame.size.width;
        self.baseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, baseSize, baseSize)];
        self.baseView.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.65];
        self.baseView.layer.cornerRadius = baseSize / 2.0;
        self.baseView.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.45].CGColor;
        self.baseView.layer.borderWidth = 1.8;
        self.baseView.userInteractionEnabled = NO;
        [self addSubview:self.baseView];

        // Center target dot
        UIView *centerDot = [[UIView alloc] initWithFrame:CGRectMake((baseSize - 8) / 2.0, (baseSize - 8) / 2.0, 8, 8)];
        centerDot.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.5];
        centerDot.layer.cornerRadius = 4;
        centerDot.userInteractionEnabled = NO;
        [self.baseView addSubview:centerDot];

        CGFloat knobSize = 46.0;
        self.knobView = [[UIView alloc] initWithFrame:CGRectMake((baseSize - knobSize) / 2.0, (baseSize - knobSize) / 2.0, knobSize, knobSize)];
        self.knobView.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:0.90];
        self.knobView.layer.cornerRadius = knobSize / 2.0;
        self.knobView.layer.borderColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.95].CGColor;
        self.knobView.layer.borderWidth = 2.0;
        self.knobView.userInteractionEnabled = NO;

        UILabel *knobIcon = [[UILabel alloc] initWithFrame:self.knobView.bounds];
        knobIcon.text = @"🕹️";
        knobIcon.textAlignment = NSTextAlignmentCenter;
        knobIcon.font = [UIFont systemFontOfSize:15];
        knobIcon.userInteractionEnabled = NO;
        [self.knobView addSubview:knobIcon];

        [self addSubview:self.knobView];
    }
    return self;
}

- (void)setKnobOffset:(CGPoint)offset {
    CGFloat centerX = self.bounds.size.width / 2.0;
    CGFloat centerY = self.bounds.size.height / 2.0;
    self.knobView.center = CGPointMake(centerX + offset.x, centerY + offset.y);
}

- (void)resetKnob {
    CGFloat centerX = self.bounds.size.width / 2.0;
    CGFloat centerY = self.bounds.size.height / 2.0;
    [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.knobView.center = CGPointMake(centerX, centerY);
    } completion:nil];
}

@end

// -----------------------------------------------------------------------------
// DiroDroneOverlayView: High-Tech Cinematic Drone HUD
// -----------------------------------------------------------------------------
@interface DiroDroneOverlayView : UIView
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) DiroVirtualJoystickView *joystick;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *ascendBtn;
@property (nonatomic, strong) UIButton *descendBtn;
@property (nonatomic, strong) UIButton *speedBtn;
@property (nonatomic, strong) UIButton *zoomMinusBtn;
@property (nonatomic, strong) UIButton *zoomPlusBtn;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UIButton *btn169;
@property (nonatomic, strong) UIButton *btn916;
@property (nonatomic, strong) UIButton *rollToggleBtn;
@property (nonatomic, strong) UIView *rollPanel;
@property (nonatomic, strong) UISlider *rollSlider;
@property (nonatomic, strong) UILabel *rollLabel;
@property (nonatomic, strong) UIButton *freezeBtn;
@property (nonatomic, strong) UIButton *teleportBtn;
@property (nonatomic, strong) UIButton *hideHudBtn;
@property (nonatomic, strong) UIButton *exitBtn;
@property (nonatomic, strong) UIButton *miniRestoreBtn;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) NSTimer *toastTimer;

// Flight dynamics
@property (nonatomic, assign) float droneX;
@property (nonatomic, assign) float droneY;
@property (nonatomic, assign) float droneZ;
@property (nonatomic, assign) float velX;
@property (nonatomic, assign) float velY;
@property (nonatomic, assign) float velZ;
@property (nonatomic, assign) float yaw;
@property (nonatomic, assign) float pitch;
@property (nonatomic, assign) float targetYaw;
@property (nonatomic, assign) float targetPitch;
@property (nonatomic, assign) float rollAngle; // in radians
@property (nonatomic, assign) float currentFOV;
@property (nonatomic, assign) float speedMultiplier;
@property (nonatomic, assign) float elevInput;
@property (nonatomic, assign) float stickX;
@property (nonatomic, assign) float stickY;
@property (nonatomic, assign) BOOL isWorldFrozen;
@property (nonatomic, assign) BOOL isHudHidden;
@property (nonatomic, assign) BOOL isActive;

// Touch tracking
@property (nonatomic, strong) UITouch *joystickTouch;
@property (nonatomic, strong) UITouch *lookTouch;
@property (nonatomic, assign) CGPoint lastLookPoint;

@property (nonatomic, copy) void (^onExitBlock)(void);
@end

@implementation DiroDroneOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = YES;

        self.currentFOV = 70.0f;
        self.speedMultiplier = 1.5f;
        self.elevInput = 0.0f;
        self.stickX = 0.0f;
        self.stickY = 0.0f;
        self.rollAngle = 0.0f;
        self.isWorldFrozen = NO;
        self.isHudHidden = NO;
        self.isActive = NO;

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 1. Left Virtual Joystick (visual feedback)
    self.joystick = [[DiroVirtualJoystickView alloc] initWithFrame:CGRectMake(0, 0, 115, 115)];
    [self addSubview:self.joystick];

    // 3. Right Elevation Buttons (⬆️ / ⬇️)
    self.ascendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.ascendBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.75];
    self.ascendBtn.layer.cornerRadius = 26.0;
    self.ascendBtn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.85].CGColor;
    self.ascendBtn.layer.borderWidth = 1.8;
    [self.ascendBtn setTitle:@"⬆️" forState:UIControlStateNormal];
    self.ascendBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    [self.ascendBtn addTarget:self action:@selector(ascendDown) forControlEvents:UIControlEventTouchDown];
    [self.ascendBtn addTarget:self action:@selector(elevUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:self.ascendBtn];

    self.descendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.descendBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.75];
    self.descendBtn.layer.cornerRadius = 26.0;
    self.descendBtn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.85].CGColor;
    self.descendBtn.layer.borderWidth = 1.8;
    [self.descendBtn setTitle:@"⬇️" forState:UIControlStateNormal];
    self.descendBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    [self.descendBtn addTarget:self action:@selector(descendDown) forControlEvents:UIControlEventTouchDown];
    [self.descendBtn addTarget:self action:@selector(elevUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:self.descendBtn];

    // 4. Top Toolbar View
    self.topBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.topBar.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.11 alpha:0.90];
    self.topBar.layer.cornerRadius = 10.0;
    self.topBar.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.65].CGColor;
    self.topBar.layer.borderWidth = 1.2;
    self.topBar.clipsToBounds = YES;
    [self addSubview:self.topBar];

    [self setupTopBarContents];

    // 5. Roll & Tilt Control Panel (Slayder bilan erkin bukish rejimi)
    self.rollPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.rollPanel.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:0.95];
    self.rollPanel.layer.cornerRadius = 10.0;
    self.rollPanel.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.75].CGColor;
    self.rollPanel.layer.borderWidth = 1.2;
    self.rollPanel.clipsToBounds = YES;
    self.rollPanel.hidden = YES;
    [self addSubview:self.rollPanel];

    [self setupRollPanelContents];

    // 6. Mini Restore Pill (shown only when HUD is hidden)
    self.miniRestoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.miniRestoreBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:0.75];
    self.miniRestoreBtn.layer.cornerRadius = 8.0;
    self.miniRestoreBtn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.7].CGColor;
    self.miniRestoreBtn.layer.borderWidth = 1.0;
    [self.miniRestoreBtn setTitle:@"👁️ HUD" forState:UIControlStateNormal];
    [self.miniRestoreBtn setTitleColor:[UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0] forState:UIControlStateNormal];
    self.miniRestoreBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    [self.miniRestoreBtn addTarget:self action:@selector(toggleHudVisibility) forControlEvents:UIControlEventTouchUpInside];
    self.miniRestoreBtn.hidden = YES;
    [self addSubview:self.miniRestoreBtn];

    // 7. Toast Notification Banner
    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.toastLabel.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:0.92];
    self.toastLabel.layer.cornerRadius = 6;
    self.toastLabel.layer.borderColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.8].CGColor;
    self.toastLabel.layer.borderWidth = 1.0;
    self.toastLabel.clipsToBounds = YES;
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    self.toastLabel.font = [UIFont boldSystemFontOfSize:11];
    self.toastLabel.textColor = [UIColor whiteColor];
    self.toastLabel.hidden = YES;
    [self addSubview:self.toastLabel];
}

- (void)setupTopBarContents {
    CGFloat x = 6.0;
    CGFloat btnH = 28.0;
    CGFloat gap = 4.0;

    // Badge
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(x, 6, 50, btnH)];
    badge.text = @"🛸 DRON";
    badge.font = [UIFont boldSystemFontOfSize:10];
    badge.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.15];
    badge.layer.cornerRadius = 5;
    badge.clipsToBounds = YES;
    [self.topBar addSubview:badge];
    x += 50 + gap;

    // Speed button
    self.speedBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.speedBtn.frame = CGRectMake(x, 6, 50, btnH);
    self.speedBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.speedBtn.layer.cornerRadius = 5;
    self.speedBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.speedBtn.layer.borderWidth = 0.8;
    [self.speedBtn setTitle:@"⚡ 1.5x" forState:UIControlStateNormal];
    [self.speedBtn setTitleColor:[UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0] forState:UIControlStateNormal];
    self.speedBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    [self.speedBtn addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.speedBtn];
    x += 50 + gap;

    // Zoom Minus
    self.zoomMinusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.zoomMinusBtn.frame = CGRectMake(x, 6, 26, btnH);
    self.zoomMinusBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.zoomMinusBtn.layer.cornerRadius = 5;
    [self.zoomMinusBtn setTitle:@"➖" forState:UIControlStateNormal];
    self.zoomMinusBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.zoomMinusBtn addTarget:self action:@selector(zoomMinusTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.zoomMinusBtn];
    x += 26 + 2;

    // FOV Label
    self.fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, 6, 32, btnH)];
    self.fovLabel.text = @"70°";
    self.fovLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.fovLabel.textColor = [UIColor whiteColor];
    self.fovLabel.textAlignment = NSTextAlignmentCenter;
    [self.topBar addSubview:self.fovLabel];
    x += 32 + 2;

    // Zoom Plus
    self.zoomPlusBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.zoomPlusBtn.frame = CGRectMake(x, 6, 26, btnH);
    self.zoomPlusBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.zoomPlusBtn.layer.cornerRadius = 5;
    [self.zoomPlusBtn setTitle:@"➕" forState:UIControlStateNormal];
    self.zoomPlusBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.zoomPlusBtn addTarget:self action:@selector(zoomPlusTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.zoomPlusBtn];
    x += 26 + gap;

    // 16:9 Standard Landscape Preset Button
    self.btn169 = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn169.frame = CGRectMake(x, 6, 52, btnH);
    self.btn169.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
    self.btn169.layer.cornerRadius = 5;
    self.btn169.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.btn169.layer.borderWidth = 0.8;
    [self.btn169 setTitle:@"📐 16:9" forState:UIControlStateNormal];
    [self.btn169 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.btn169.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    [self.btn169 addTarget:self action:@selector(btn169Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.btn169];
    x += 52 + gap;

    // 9:16 Vertical Portrait Preset Button (TikTok / Reels / Shorts)
    self.btn916 = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn916.frame = CGRectMake(x, 6, 52, btnH);
    self.btn916.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.btn916.layer.cornerRadius = 5;
    self.btn916.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.btn916.layer.borderWidth = 0.8;
    [self.btn916 setTitle:@"📱 9:16" forState:UIControlStateNormal];
    [self.btn916 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn916.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    [self.btn916 addTarget:self action:@selector(btn916Tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.btn916];
    x += 52 + gap;

    // Roll / Tilt Panel Toggle Button (Shows live degrees)
    self.rollToggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.rollToggleBtn.frame = CGRectMake(x, 6, 54, btnH);
    self.rollToggleBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.rollToggleBtn.layer.cornerRadius = 5;
    self.rollToggleBtn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.6].CGColor;
    self.rollToggleBtn.layer.borderWidth = 0.8;
    [self.rollToggleBtn setTitle:@"🔄 0°" forState:UIControlStateNormal];
    [self.rollToggleBtn setTitleColor:[UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0] forState:UIControlStateNormal];
    self.rollToggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    [self.rollToggleBtn addTarget:self action:@selector(toggleRollPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.rollToggleBtn];
    x += 54 + gap;

    // Teleport CJ
    self.teleportBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.teleportBtn.frame = CGRectMake(x, 6, 52, btnH);
    self.teleportBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.teleportBtn.layer.cornerRadius = 5;
    self.teleportBtn.layer.borderColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:0.4].CGColor;
    self.teleportBtn.layer.borderWidth = 0.8;
    [self.teleportBtn setTitle:@"📍 CJ" forState:UIControlStateNormal];
    [self.teleportBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.teleportBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [self.teleportBtn addTarget:self action:@selector(teleportTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.teleportBtn];
    x += 52 + gap;

    // Freeze World
    self.freezeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.freezeBtn.frame = CGRectMake(x, 6, 50, btnH);
    self.freezeBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.freezeBtn.layer.cornerRadius = 5;
    self.freezeBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.freezeBtn.layer.borderWidth = 0.8;
    [self.freezeBtn setTitle:@"🧊 Muz" forState:UIControlStateNormal];
    [self.freezeBtn setTitleColor:[UIColor colorWithRed:0.40 green:0.85 blue:1.00 alpha:1.0] forState:UIControlStateNormal];
    self.freezeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [self.freezeBtn addTarget:self action:@selector(freezeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.freezeBtn];
    x += 50 + gap;

    // Hide HUD
    self.hideHudBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.hideHudBtn.frame = CGRectMake(x, 6, 28, btnH);
    self.hideHudBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
    self.hideHudBtn.layer.cornerRadius = 5;
    [self.hideHudBtn setTitle:@"👁️" forState:UIControlStateNormal];
    self.hideHudBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.hideHudBtn addTarget:self action:@selector(toggleHudVisibility) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.hideHudBtn];
    x += 28 + gap;

    // Exit
    self.exitBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.exitBtn.frame = CGRectMake(x, 6, 28, btnH);
    self.exitBtn.backgroundColor = [UIColor colorWithRed:0.80 green:0.15 blue:0.15 alpha:1.0];
    self.exitBtn.layer.cornerRadius = 5;
    [self.exitBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.exitBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exitBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.exitBtn addTarget:self action:@selector(exitTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.exitBtn];
}

- (UIButton *)createRollPresetBtn:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.24 alpha:1.0];
    btn.layer.cornerRadius = 4.0;
    btn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    btn.layer.borderWidth = 0.7;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)setupRollPanelContents {
    // 1. Roll Angle Status Label
    self.rollLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 175, 22)];
    self.rollLabel.text = @"🔄 Burchak: 0.0° [16:9]";
    self.rollLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.rollLabel.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
    [self.rollPanel addSubview:self.rollLabel];

    // 2. Preset Buttons: 0° (16:9), 90° (9:16), -45°, +45°, 180°
    CGFloat bx = 188.0;
    CGFloat bh = 22.0;

    UIButton *b0 = [self createRollPresetBtn:@"📐 0°" frame:CGRectMake(bx, 6, 44, bh) action:@selector(setRoll0)];
    [self.rollPanel addSubview:b0];
    bx += 44 + 4;

    UIButton *b90 = [self createRollPresetBtn:@"📱 90°" frame:CGRectMake(bx, 6, 48, bh) action:@selector(setRoll90)];
    [self.rollPanel addSubview:b90];
    bx += 48 + 4;

    UIButton *bm45 = [self createRollPresetBtn:@"↩️ -45°" frame:CGRectMake(bx, 6, 52, bh) action:@selector(setRollMinus45)];
    [self.rollPanel addSubview:bm45];
    bx += 52 + 4;

    UIButton *bp45 = [self createRollPresetBtn:@"↪️ +45°" frame:CGRectMake(bx, 6, 52, bh) action:@selector(setRoll45)];
    [self.rollPanel addSubview:bp45];
    bx += 52 + 4;

    UIButton *b180 = [self createRollPresetBtn:@"🔄 180°" frame:CGRectMake(bx, 6, 54, bh) action:@selector(setRoll180)];
    [self.rollPanel addSubview:b180];

    // Close panel button
    UIButton *closePanelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closePanelBtn.frame = CGRectMake(452, 6, 22, 22);
    closePanelBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    closePanelBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
    closePanelBtn.layer.cornerRadius = 4;
    [closePanelBtn setTitle:@"✕" forState:UIControlStateNormal];
    closePanelBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [closePanelBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closePanelBtn addTarget:self action:@selector(toggleRollPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.rollPanel addSubview:closePanelBtn];

    // 3. Slider Row: -180° [=======O=======] +180°
    UILabel *minLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 36, 40, 22)];
    minLbl.text = @"-180°";
    minLbl.font = [UIFont boldSystemFontOfSize:9.5];
    minLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    minLbl.textAlignment = NSTextAlignmentRight;
    [self.rollPanel addSubview:minLbl];

    self.rollSlider = [[UISlider alloc] initWithFrame:CGRectMake(52, 34, 376, 26)];
    self.rollSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.rollSlider.minimumValue = -180.0f;
    self.rollSlider.maximumValue = 180.0f;
    self.rollSlider.value = 0.0f;
    self.rollSlider.continuous = YES;
    self.rollSlider.minimumTrackTintColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
    self.rollSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.30 alpha:1.0];
    self.rollSlider.thumbTintColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
    [self.rollSlider addTarget:self action:@selector(rollSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.rollPanel addSubview:self.rollSlider];

    UILabel *maxLbl = [[UILabel alloc] initWithFrame:CGRectMake(432, 36, 40, 22)];
    maxLbl.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    maxLbl.text = @"+180°";
    maxLbl.font = [UIFont boldSystemFontOfSize:9.5];
    maxLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    maxLbl.textAlignment = NSTextAlignmentLeft;
    [self.rollPanel addSubview:maxLbl];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isActive || self.hidden || self.alpha < 0.01) {
        return nil;
    }
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit && hit != self && hit != self.joystick && hit != self.joystick.baseView && hit != self.joystick.knobView) {
        return hit;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat tbW = MIN(550.0, w - 16.0);
    self.topBar.frame = CGRectMake((w - tbW) / 2.0, 10.0, tbW, 40.0);

    CGFloat rpW = MIN(480.0, w - 20.0);
    self.rollPanel.frame = CGRectMake((w - rpW) / 2.0, 54.0, rpW, 68.0);

    self.miniRestoreBtn.frame = CGRectMake(w - 70.0, 12.0, 58.0, 32.0);
    self.toastLabel.frame = CGRectMake((w - 340.0) / 2.0, (self.rollPanel.hidden ? 56.0 : 126.0), 340.0, 24.0);

    self.joystick.frame = CGRectMake(35.0, h - 145.0, 115.0, 115.0);

    CGFloat ebX = w - 70.0;
    CGFloat ebY = h - 145.0;
    self.ascendBtn.frame = CGRectMake(ebX, ebY, 52.0, 52.0);
    self.descendBtn.frame = CGRectMake(ebX, ebY + 60.0, 52.0, 52.0);
}

- (void)updateJoystickWithPoint:(CGPoint)pt {
    CGPoint center = self.joystick.center;
    CGFloat dx = pt.x - center.x;
    CGFloat dy = pt.y - center.y;
    CGFloat maxR = (self.joystick.bounds.size.width - 46.0) / 2.0;
    if (maxR < 25.0) maxR = 35.0;

    CGFloat dist = sqrtf(dx * dx + dy * dy);
    if (dist > maxR && dist > 0.001f) {
        dx = (dx / dist) * maxR;
        dy = (dy / dist) * maxR;
    }

    [self.joystick setKnobOffset:CGPointMake(dx, dy)];
    self.stickX = (float)(dx / maxR);
    self.stickY = (float)(-dy / maxR); // Up is forward (+1.0)
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGFloat w = self.bounds.size.width;
    CGFloat splitX = w * 0.45;

    for (UITouch *t in touches) {
        CGPoint pt = [t locationInView:self];
        if (pt.x < splitX) {
            if (!self.joystickTouch) {
                self.joystickTouch = t;
                [self updateJoystickWithPoint:pt];
            }
        } else {
            if (!self.lookTouch) {
                self.lookTouch = t;
                self.lastLookPoint = pt;
            }
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) {
        if (t == self.joystickTouch) {
            CGPoint pt = [t locationInView:self];
            [self updateJoystickWithPoint:pt];
        } else if (t == self.lookTouch) {
            CGPoint pt = [t locationInView:self];
            CGFloat dx = pt.x - self.lastLookPoint.x;
            CGFloat dy = pt.y - self.lastLookPoint.y;
            self.lastLookPoint = pt;

            self.targetYaw += (float)dx * 0.0045f;
            self.targetPitch -= (float)dy * 0.0045f;
            if (self.targetPitch > 1.45f) self.targetPitch = 1.45f;
            if (self.targetPitch < -1.45f) self.targetPitch = -1.45f;
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) {
        if (t == self.joystickTouch) {
            self.joystickTouch = nil;
            self.stickX = 0.0f;
            self.stickY = 0.0f;
            [self.joystick resetKnob];
        }
        if (t == self.lookTouch) {
            if (t.tapCount == 2) {
                [self toggleHudVisibility];
            }
            self.lookTouch = nil;
        }
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)ascendDown {
    self.elevInput = 1.0f;
}

- (void)descendDown {
    self.elevInput = -1.0f;
}

- (void)elevUp {
    self.elevInput = 0.0f;
}

- (void)speedTapped {
    if (self.speedMultiplier < 1.0f) {
        self.speedMultiplier = 1.5f;
        [self.speedBtn setTitle:@"⚡ 1.5x" forState:UIControlStateNormal];
        [self showToast:@"⚡ Parvoz tezligi: 1.5x (Standart)"];
    } else if (self.speedMultiplier < 2.5f) {
        self.speedMultiplier = 4.0f;
        [self.speedBtn setTitle:@"🚀 4.0x" forState:UIControlStateNormal];
        [self showToast:@"🚀 Parvoz tezligi: 4.0x (Tezkor FPV)"];
    } else if (self.speedMultiplier < 6.0f) {
        self.speedMultiplier = 10.0f;
        [self.speedBtn setTitle:@"🔥 10x" forState:UIControlStateNormal];
        [self showToast:@"🔥 Parvoz tezligi: 10.0x (Turbo Super)"];
    } else {
        self.speedMultiplier = 0.5f;
        [self.speedBtn setTitle:@"🐢 0.5x" forState:UIControlStateNormal];
        [self showToast:@"🐢 Parvoz tezligi: 0.5x (Kinematografik Sekin)"];
    }
}

- (void)zoomMinusTapped {
    if (self.currentFOV > 20.0f) {
        self.currentFOV -= 15.0f;
        if (self.currentFOV < 15.0f) self.currentFOV = 15.0f;
        self.fovLabel.text = [NSString stringWithFormat:@"%.0f°", self.currentFOV];
        camera_set_fov(self.currentFOV);
        [self applyCameraToGame];
        [self showToast:[NSString stringWithFormat:@"🔍 Zoom Yaqinlashdi: %.0f°", self.currentFOV]];
    }
}

- (void)zoomPlusTapped {
    if (self.currentFOV < 100.0f) {
        self.currentFOV += 15.0f;
        if (self.currentFOV > 105.0f) self.currentFOV = 105.0f;
        self.fovLabel.text = [NSString stringWithFormat:@"%.0f°", self.currentFOV];
        camera_set_fov(self.currentFOV);
        [self applyCameraToGame];
        [self showToast:[NSString stringWithFormat:@"🔍 Keng Burchak (Wide): %.0f°", self.currentFOV]];
    }
}

- (void)btn169Tapped {
    [self setRollDegrees:0.0f];
    [self showToast:@"📐 Standart 16:9 Landshaft rejim (Normal tekis gorizont)!"];
}

- (void)btn916Tapped {
    [self setRollDegrees:90.0f];
    [self showToast:@"📱 Vertikal 9:16 rejim (TikTok / Reels / Shorts formati)!"];
}

- (void)toggleRollPanel {
    self.rollPanel.hidden = !self.rollPanel.hidden;
    if (!self.rollPanel.hidden) {
        [self bringSubviewToFront:self.rollPanel];
    }
    [self setNeedsLayout];
}

- (void)setRollDegrees:(float)deg {
    [self updateRollUIWithDegrees:deg];
}

- (void)setRoll0 {
    [self setRollDegrees:0.0f];
    [self showToast:@"📐 16:9 Rejim (0° Gorizontal)"];
}

- (void)setRoll90 {
    [self setRollDegrees:90.0f];
    [self showToast:@"📱 9:16 Rejim (+90° Vertikal TikTok)"];
}

- (void)setRollMinus45 {
    [self setRollDegrees:-45.0f];
    [self showToast:@"↩️ -45° Kinematografik burchak"];
}

- (void)setRoll45 {
    [self setRollDegrees:45.0f];
    [self showToast:@"↪️ +45° Kinematografik burchak"];
}

- (void)setRoll180 {
    [self setRollDegrees:180.0f];
    [self showToast:@"🔄 180° Teskari burchak"];
}

- (void)rollSliderChanged:(UISlider *)slider {
    float deg = slider.value;
    // Magnetic snap to cardinal angles
    if (fabsf(deg) < 2.5f) deg = 0.0f;
    else if (fabsf(deg - 90.0f) < 2.5f) deg = 90.0f;
    else if (fabsf(deg + 90.0f) < 2.5f) deg = -90.0f;
    else if (fabsf(deg - 45.0f) < 2.0f) deg = 45.0f;
    else if (fabsf(deg + 45.0f) < 2.0f) deg = -45.0f;
    else if (fabsf(deg - 180.0f) < 2.5f) deg = 180.0f;
    else if (fabsf(deg + 180.0f) < 2.5f) deg = -180.0f;

    [self updateRollUIWithDegrees:deg];
}

- (void)updateRollUIWithDegrees:(float)deg {
    self.rollAngle = deg * (float)(M_PI / 180.0);
    self.rollSlider.value = deg;

    NSString *modeName = @"Erkin Qiyalik";
    if (fabsf(deg) < 1.0f) {
        modeName = @"16:9 Landshaft";
    } else if (fabsf(deg - 90.0f) < 1.0f) {
        modeName = @"9:16 Vertikal";
    } else if (fabsf(deg + 90.0f) < 1.0f) {
        modeName = @"9:16 Vertikal (-)";
    } else if (fabsf(fabsf(deg) - 180.0f) < 1.0f) {
        modeName = @"180° Teskari";
    }

    self.rollLabel.text = [NSString stringWithFormat:@"🔄 Burchak: %+.1f° [%@]", deg, modeName];
    [self.rollToggleBtn setTitle:[NSString stringWithFormat:@"🔄 %+.0f°", deg] forState:UIControlStateNormal];

    // Highlight 16:9 button if angle is 0
    if (fabsf(deg) < 1.0f) {
        self.btn169.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        [self.btn169 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    } else {
        self.btn169.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
        [self.btn169 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }

    // Highlight 9:16 button if angle is 90
    if (fabsf(deg - 90.0f) < 1.0f) {
        self.btn916.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        [self.btn916 setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    } else {
        self.btn916.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
        [self.btn916 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }

    set_game_rotation(self.rollAngle);
    [self applyCameraToGame];
}

- (void)freezeTapped {
    self.isWorldFrozen = !self.isWorldFrozen;
    set_game_frozen(self.isWorldFrozen);
    if (self.isWorldFrozen) {
        self.freezeBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.40 blue:0.60 alpha:1.0];
        [self.freezeBtn setTitle:@"❄️ Muzladi" forState:UIControlStateNormal];
        [self showToast:@"❄️ Butun dunyo to'xtatildi (Freeze World)!"];
    } else {
        self.freezeBtn.backgroundColor = [UIColor colorWithRed:0.16 green:0.16 blue:0.22 alpha:1.0];
        [self.freezeBtn setTitle:@"🧊 Muz" forState:UIControlStateNormal];
        [self showToast:@"▶️ O'yin vaqti tiklandi!"];
    }
}

- (void)teleportTapped {
    teleport_player_to_coords(self.droneX, self.droneY, self.droneZ - 1.2f);
    [self showToast:@"✅ CJ dron turgan joyga teleport qilindi!"];
}

- (void)toggleHudVisibility {
    self.isHudHidden = !self.isHudHidden;
    self.topBar.hidden = self.isHudHidden;
    self.rollPanel.hidden = YES; // Always hide roll panel when HUD is hidden
    self.joystick.hidden = self.isHudHidden;
    self.ascendBtn.hidden = self.isHudHidden;
    self.descendBtn.hidden = self.isHudHidden;
    self.miniRestoreBtn.hidden = !self.isHudHidden;

    if (self.isHudHidden) {
        [self showToast:@"💡 Ekranga 2 marta teginsangiz, tugmalar qaytadi"];
    }
}

- (void)showToast:(NSString *)msg {
    self.toastLabel.text = msg;
    self.toastLabel.alpha = 1.0;
    self.toastLabel.hidden = NO;
    [self.toastTimer invalidate];
    self.toastTimer = [NSTimer scheduledTimerWithTimeInterval:2.2 target:self selector:@selector(hideToast) userInfo:nil repeats:NO];
}

- (void)hideToast {
    [UIView animateWithDuration:0.25 animations:^{
        self.toastLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.toastLabel.hidden = YES;
    }];
}

- (void)startDroneFlight {
    self.isActive = YES;
    if (g_floatingButton) g_floatingButton.hidden = YES;

    // Hide GTA SA native HUD & mobile buttons
    set_game_hud_visible(NO);

    uintptr_t cam = get_the_camera();
    uintptr_t ped = get_player_ped();
    float px = 0.0f, py = 0.0f, pz = 0.0f;
    if (ped) {
        get_entity_position(ped, &px, &py, &pz);
    }
    if (px == 0.0f && py == 0.0f && pz == 0.0f) {
        if (cam) {
            px = *(float *)(cam + 0x9a0);
            py = *(float *)(cam + 0x9a4);
            pz = *(float *)(cam + 0x9a8);
        }
    }
    self.droneX = px;
    self.droneY = py;
    self.droneZ = pz + 2.5f;

    // Smoothly inherit current camera look angle to avoid camera jerk/snap
    float initYaw = 0.0f;
    float initPitch = -0.05f;
    if (cam) {
        float fwdX = *(float *)(cam + 0x990);
        float fwdY = *(float *)(cam + 0x994);
        float fwdZ = *(float *)(cam + 0x998);
        float lenH = sqrtf(fwdX * fwdX + fwdY * fwdY);
        if (lenH > 0.01f) {
            initYaw = atan2f(fwdX, fwdY);
            initPitch = asinf(fminf(fmaxf(fwdZ, -0.95f), 0.95f));
        }
    }

    self.yaw = initYaw;
    self.pitch = initPitch;
    self.targetYaw = self.yaw;
    self.targetPitch = self.pitch;
    self.velX = self.velY = self.velZ = 0.0f;
    self.elevInput = 0.0f;
    self.stickX = 0.0f;
    self.stickY = 0.0f;
    self.joystickTouch = nil;
    self.lookTouch = nil;

    // Reset roll to 0.0° (16:9 standard landscape)
    self.rollAngle = 0.0f;
    self.rollPanel.hidden = YES;
    [self updateRollUIWithDegrees:0.0f];

    // Take camera control
    float camTarget[3] = {
        self.droneX + sinf(self.yaw) * cosf(self.pitch) * 25.0f,
        self.droneY + cosf(self.yaw) * cosf(self.pitch) * 25.0f,
        self.droneZ + sinf(self.pitch) * 25.0f
    };
    camera_take_control(camTarget, 2);

    // Apply initial position immediately
    [self applyCameraToGame];

    // Start 60 FPS update loop
    [self.displayLink invalidate];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrameUpdate:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [self showToast:@"🛸 Dron faollashdi! Chapda joystik, o'ngda burish."];
}

- (void)stopDroneFlight {
    self.isActive = NO;

    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }

    if (self.isWorldFrozen) {
        set_game_frozen(NO);
        self.isWorldFrozen = NO;
    }

    self.rollPanel.hidden = YES;
    camera_set_fov(70.0f);
    camera_restore();

    // Restore GTA SA native HUD & mobile buttons
    set_game_hud_visible(YES);

    // Reset game view rotation to 16:9 standard landscape
    set_game_rotation(0.0f);
}

- (void)exitTapped {
    [self stopDroneFlight];
    set_game_rotation(0.0f);
    if (g_floatingButton) g_floatingButton.hidden = NO;
    [self removeFromSuperview];
    if (self.onExitBlock) {
        self.onExitBlock();
    }
}

- (void)onFrameUpdate:(CADisplayLink *)link {
    if (!self.isActive) return;

    float dt = (link.duration > 0.001) ? (float)link.duration : (1.0f / 60.0f);
    if (dt > 0.1f) dt = 1.0f / 60.0f;

    float cosPitch = cosf(self.pitch);
    float sinPitch = sinf(self.pitch);
    float cosYaw = cosf(self.yaw);
    float sinYaw = sinf(self.yaw);

    // Camera forward vector in world coordinates
    float fwdX = sinYaw * cosPitch;
    float fwdY = cosYaw * cosPitch;
    float fwdZ = sinPitch;

    // Camera right vector (strafe horizontal)
    float rightX = cosYaw;
    float rightY = -sinYaw;

    float baseSpeed = 15.0f;
    float speed = baseSpeed * self.speedMultiplier;

    float targetVx = (fwdX * self.stickY + rightX * self.stickX) * speed;
    float targetVy = (fwdY * self.stickY + rightY * self.stickX) * speed;
    float targetVz = (fwdZ * self.stickY + self.elevInput) * speed;

    // Exponential smoothing / damping
    float posDamping = 0.30f;
    self.velX += (targetVx - self.velX) * posDamping;
    self.velY += (targetVy - self.velY) * posDamping;
    self.velZ += (targetVz - self.velZ) * posDamping;

    self.droneX += self.velX * dt;
    self.droneY += self.velY * dt;
    self.droneZ += self.velZ * dt;

    // Angular smoothing for look direction
    float rotDamping = 0.40f;
    self.yaw += (self.targetYaw - self.yaw) * rotDamping;
    self.pitch += (self.targetPitch - self.pitch) * rotDamping;

    [self applyCameraToGame];
}

- (void)applyCameraToGame {
    uintptr_t cam = get_the_camera();
    if (!cam) return;

    float cosPitch = cosf(self.pitch);
    float sinPitch = sinf(self.pitch);
    float cosYaw = cosf(self.yaw);
    float sinYaw = sinf(self.yaw);

    // 1. Forward (look) vector in GTA SA world coordinates (+X East, +Y North, +Z Up)
    float fwdX = sinYaw * cosPitch;
    float fwdY = cosYaw * cosPitch;
    float fwdZ = sinPitch;

    // 2. Base horizontal Right vector (orthogonal to fwd when pitch=0, roll=0)
    float baseRightX = cosYaw;
    float baseRightY = -sinYaw;
    float baseRightZ = 0.0f;

    // 3. Base Up vector = cross(baseRight, fwd)
    // cross(A, B): (Ay*Bz - Az*By, Az*Bx - Ax*Bz, Ax*By - Ay*Bx)
    float baseUpX = baseRightY * fwdZ;
    float baseUpY = -baseRightX * fwdZ;
    float baseUpZ = baseRightX * fwdY - baseRightY * fwdX;

    // 4. Continuous roll rotation around look axis (fwd) by self.rollAngle
    float cosR = cosf(self.rollAngle);
    float sinR = sinf(self.rollAngle);

    // right = baseRight * cosR + baseUp * sinR
    float rightX = baseRightX * cosR + baseUpX * sinR;
    float rightY = baseRightY * cosR + baseUpY * sinR;
    float rightZ = baseRightZ * cosR + baseUpZ * sinR;

    // up = -baseRight * sinR + baseUp * cosR
    float upX = -baseRightX * sinR + baseUpX * cosR;
    float upY = -baseRightY * sinR + baseUpY * cosR;
    float upZ = -baseRightZ * sinR + baseUpZ * cosR;

    float camPos[3] = { self.droneX, self.droneY, self.droneZ };
    float camTarget[3] = {
        self.droneX + fwdX * 25.0f,
        self.droneY + fwdY * 25.0f,
        self.droneZ + fwdZ * 25.0f
    };

    uint8_t activeIdx = *(uint8_t *)(cam + 0x5f);
    if (activeIdx > 2) activeIdx = 0;
    uintptr_t activeCam = cam + (uintptr_t)activeIdx * 0x228;

    // Direct memory flags to lock camera under script/drone control (Mode 15: Point at target)
    *(int16_t *)(activeCam + 0x186) = 15;
    *(int16_t *)(cam + 0xc64) = 15;
    *(int32_t *)(cam + 0xb4) = 1;          // whoTakesControl = 1 (SCRIPT)
    *(uint8_t *)(cam + 0x54) = 0;

    // Direct target buffer assignments (0x83c is read by Mode 15 CCamera::Process!)
    *(float *)(cam + 0x83c) = camTarget[0];
    *(float *)(cam + 0x840) = camTarget[1];
    *(float *)(cam + 0x844) = camTarget[2];

    *(float *)(activeCam + 0x2a4) = camTarget[0];
    *(float *)(activeCam + 0x2a8) = camTarget[1];
    *(float *)(activeCam + 0x2ac) = camTarget[2];

    // Direct position buffer assignments
    *(float *)(cam + 0x848) = camPos[0];
    *(float *)(cam + 0x84c) = camPos[1];
    *(float *)(cam + 0x850) = camPos[2];

    *(float *)(activeCam + 0x2b0) = camPos[0];
    *(float *)(activeCam + 0x2b4) = camPos[1];
    *(float *)(activeCam + 0x2b8) = camPos[2];

    // Direct front vector assignments
    *(float *)(cam + 0x854) = fwdX;
    *(float *)(cam + 0x858) = fwdY;
    *(float *)(cam + 0x85c) = fwdZ;

    *(float *)(activeCam + 0x2bc) = fwdX;
    *(float *)(activeCam + 0x2c0) = fwdY;
    *(float *)(activeCam + 0x2c4) = fwdZ;

    // Direct up vector assignments
    *(float *)(activeCam + 0x2c8) = upX;
    *(float *)(activeCam + 0x2cc) = upY;
    *(float *)(activeCam + 0x2d0) = upZ;

    // Set FOV in activeCam and TheCamera
    *(float *)(activeCam + 0x8c) = self.currentFOV;
    *(float *)(activeCam + 0x90) = self.currentFOV;
    *(float *)(activeCam + 0x94) = self.currentFOV;
    *(float *)(cam + 0xd0) = self.currentFOV;

    // Direct TheCamera.m_mCameraMatrix update (RenderWare RwMatrix)
    // 0x970: right vector
    *(float *)(cam + 0x970) = rightX;
    *(float *)(cam + 0x974) = rightY;
    *(float *)(cam + 0x978) = rightZ;

    // 0x980: up vector
    *(float *)(cam + 0x980) = upX;
    *(float *)(cam + 0x984) = upY;
    *(float *)(cam + 0x988) = upZ;

    // 0x990: at / forward vector
    *(float *)(cam + 0x990) = fwdX;
    *(float *)(cam + 0x994) = fwdY;
    *(float *)(cam + 0x998) = fwdZ;

    // 0x9a0: position vector
    *(float *)(cam + 0x9a0) = camPos[0];
    *(float *)(cam + 0x9a4) = camPos[1];
    *(float *)(cam + 0x9a8) = camPos[2];
}

@end

// -----------------------------------------------------------------------------
// DiroMenuModal: Full Modern Cheat Hub with 6 Categories
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

    // Category segmented control (6 tabs)
    NSArray *categories = @[@"🚗 Avto", @"🎨 Rang", @"🛸 Dron", @"🛡️ O'yinchi", @"🔫 Qurol", @"⏰ Vaqt"];
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
    // Category 2: Dron & Erkin Kamera (Cinematic Drone / Free Camera)
    // =========================================================================
    if (cat == 2) {
        // Hero Card with Start Button
        UIView *heroCard = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, 82)];
        heroCard.backgroundColor = [UIColor colorWithRed:0.11 green:0.12 blue:0.18 alpha:1.0];
        heroCard.layer.cornerRadius = 10.0;
        heroCard.layer.borderColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:0.8].CGColor;
        heroCard.layer.borderWidth = 1.2;
        heroCard.clipsToBounds = YES;

        UILabel *droneTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, btnW - 20, 18)];
        droneTitle.text = @"🛸 KINEMATOGRAFIK DRON & ERKIN KAMERA";
        droneTitle.font = [UIFont boldSystemFontOfSize:12.5];
        droneTitle.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
        [heroCard addSubview:droneTitle];

        UIButton *startDroneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        startDroneBtn.frame = CGRectMake(10, 32, btnW - 20, 42);
        startDroneBtn.backgroundColor = [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0];
        startDroneBtn.layer.cornerRadius = 8.0;
        [startDroneBtn setTitle:@"🚀 DRONNI ISHGA TUSHIRISH (START)" forState:UIControlStateNormal];
        [startDroneBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        startDroneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13.5];
        [startDroneBtn addTarget:self action:@selector(startDroneTapped) forControlEvents:UIControlEventTouchUpInside];
        [heroCard addSubview:startDroneBtn];

        [self.scrollView addSubview:heroCard];
        curY += 90.0;

        // Drone instruction and feature items
        NSArray *dFeatures = @[
            @{
                @"icon": @"🕹️",
                @"title": @"Chap Virtual Joystik",
                @"desc": @"Oldinga, orqaga, chapga va o'ngga (strafe) 60 FPS silliq harakat"
            },
            @{
                @"icon": @"👆",
                @"title": @"O'ng Sensor Maydon",
                @"desc": @"Ekranni barmog'ingiz bilan silang: 360° burilish va vertikal qarash"
            },
            @{
                @"icon": @"⬆️",
                @"title": @"Vertikal Balandlik (⬆️ / ⬇️)",
                @"desc": @"Ekranning o'ng tomonidagi tugmalar orqali osmonga ko'tarilish yoki pastlash"
            },
            @{
                @"icon": @"⚡",
                @"title": @"4 Xil Parvoz Tezligi",
                @"desc": @"0.5x (Kino/Sekin), 1.5x (Standart), 4.0x (Tezkor FPV), 10.0x (Turbo Super)"
            },
            @{
                @"icon": @"🔍",
                @"title": @"Optik Zoom & FOV",
                @"desc": @"15° (Kuchli tele-zoom) dan 105° (Keng burchakli panorama) gacha boshqarish"
            },
            @{
                @"icon": @"🧊",
                @"title": @"Dunyoni Muzlatish (Freeze World)",
                @"desc": @"O'yin vaqtini to'xtatib, havoda muzlab qolgan mashinalar atrofida uchish"
            },
            @{
                @"icon": @"📍",
                @"title": @"CJ Teleportatsiya",
                @"desc": @"Dron uchib borgan istalgan koordinataga CJ yoki mashinangizni ko'chirish"
            },
            @{
                @"icon": @"📐",
                @"title": @"16:9 & 9:16 Rejimlar (TikTok / Reels)",
                @"desc": @"Normal gorizontal 16:9 yoki bir tugma bilan TikTok vertikal 9:16 format"
            },
            @{
                @"icon": @"🔄",
                @"title": @"Erkin Qiyalik & Bukish Slayderi",
                @"desc": @"-180° dan +180° gacha istalgan burchakda silliq burish va qiyalashtirish"
            },
            @{
                @"icon": @"👁️",
                @"title": @"Kinematografik Rejim (HUD yashirish)",
                @"desc": @"Barcha tugmalarni berkitib video olish. Qaytarish uchun ekranga 2 marta bosing"
            }
        ];

        CGFloat fCardH = 46.0;
        CGFloat fGap = 6.0;
        for (NSDictionary *fDict in dFeatures) {
            UIView *fc = [[UIView alloc] initWithFrame:CGRectMake(0, curY, btnW, fCardH)];
            fc.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.16 alpha:0.9];
            fc.layer.cornerRadius = 7.0;
            fc.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
            fc.layer.borderWidth = 0.8;

            UILabel *iconLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, (fCardH - 24) / 2.0, 26, 24)];
            iconLbl.text = fDict[@"icon"];
            iconLbl.font = [UIFont systemFontOfSize:18];
            iconLbl.textAlignment = NSTextAlignmentCenter;
            [fc addSubview:iconLbl];

            UILabel *tLbl = [[UILabel alloc] initWithFrame:CGRectMake(38, 5, btnW - 46, 16)];
            tLbl.text = fDict[@"title"];
            tLbl.font = [UIFont boldSystemFontOfSize:11.5];
            tLbl.textColor = [UIColor colorWithRed:1.00 green:0.84 blue:0.00 alpha:1.0];
            [fc addSubview:tLbl];

            UILabel *dLbl = [[UILabel alloc] initWithFrame:CGRectMake(38, 22, btnW - 46, 18)];
            dLbl.text = fDict[@"desc"];
            dLbl.font = [UIFont systemFontOfSize:9.5];
            dLbl.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
            [fc addSubview:dLbl];

            [self.scrollView addSubview:fc];
            curY += fCardH + fGap;
        }

        self.scrollView.contentSize = CGSizeMake(btnW, curY + 12.0);
        return;
    }

    // =========================================================================
    // Category 3: O'yinchi (Player Health, God Mode, Money, Motion)
    // =========================================================================
    if (cat == 3) {
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
    // Category 4: Qurollar (Weapons Packs 1, 2, 3)
    // =========================================================================
    if (cat == 4) {
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
    // Category 5: Vaqt & Havo (Clock, Weather & Wanted Level)
    // =========================================================================
    if (cat == 5) {
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

- (void)startDroneTapped {
    [self hapticImpact:1];
    [self toggleVisibility];

    if (!g_droneOverlay) {
        g_droneOverlay = [[DiroDroneOverlayView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        g_droneOverlay.onExitBlock = ^{
            NSLog(@"[DIRO] Drone mode exited cleanly.");
        };
    }

    UIViewController *rootVC = g_diroWindow.rootViewController;
    if (rootVC) {
        g_droneOverlay.frame = rootVC.view.bounds;
        if (g_droneOverlay.superview != rootVC.view) {
            [rootVC.view addSubview:g_droneOverlay];
        }
        [g_droneOverlay startDroneFlight];
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
        [self showToast:@"⚠️ Yaqin atrofda mashina topilmadi! Mashina chiqaring yoki unga yaqinlashing."];
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
        [self showToast:@"⚠️ Yaqin atrofda mashina topilmadi! Mashina chiqaring yoki unga yaqinlashing."];
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
// Setup & Lifecycle using High-Priority DiroWindow Overlay
// -----------------------------------------------------------------------------
static void setup_diro_ui(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_diroWindow && !g_diroWindow.hidden && g_floatingButton && g_floatingButton.superview) {
            return;
        }

        UIWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    if (ws.activationState == UISceneActivationStateForegroundActive ||
                        ws.activationState == UISceneActivationStateForegroundInactive) {
                        window = [[DiroWindow alloc] initWithWindowScene:ws];
                        break;
                    }
                }
            }
        }
        if (!window) {
            window = [[DiroWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_diroWindow = (DiroWindow *)window;
        g_diroWindow.windowLevel = UIWindowLevelAlert + 1000.0;
        g_diroWindow.backgroundColor = [UIColor clearColor];

        DiroRootViewController *vc = [[DiroRootViewController alloc] init];
        g_diroWindow.rootViewController = vc;
        g_diroWindow.hidden = NO;

        CGSize sz = [UIScreen mainScreen].bounds.size;
        CGFloat btnSize = 52.0;
        CGFloat initialX = 14.0;
        CGFloat initialY = (sz.height - btnSize) / 2.0;

        if (!g_floatingButton) {
            g_floatingButton = [[DiroFloatingButton alloc] initWithFrame:CGRectMake(initialX, initialY, btnSize, btnSize)];
        }
        if (g_floatingButton.superview != vc.view) {
            [vc.view addSubview:g_floatingButton];
        }

        CGFloat mw = MIN(410.0, sz.width - 24.0);
        CGFloat mh = MIN(310.0, sz.height - 24.0);
        CGFloat mx = (sz.width - mw) / 2.0;
        CGFloat my = (sz.height - mh) / 2.0;

        if (!g_menuModal) {
            g_menuModal = [[DiroMenuModal alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
            g_menuModal.hidden = YES;
            g_menuModal.alpha = 0.0;
        }
        if (g_menuModal.superview != vc.view) {
            [vc.view addSubview:g_menuModal];
        }

        // Hide legacy cheat windows (iOSGods) completely so only our Diro menu is visible!
        UIApplication *app = [UIApplication sharedApplication];
        for (UIWindow *w in app.windows) {
            if (w != g_diroWindow) {
                NSString *cls = NSStringFromClass([w class]);
                if ([cls containsString:@"ButtonWindow"] || 
                    [cls containsString:@"IGWindow"] || 
                    [cls containsString:@"IGFloating"] || 
                    [cls containsString:@"iOSGods"]) {
                    w.hidden = YES;
                    w.alpha = 0.0;
                    w.userInteractionEnabled = NO;
                }
            }
        }

        NSLog(@"[DIRO] Diro Mod Menu is 100%% active and visible on screen via DiroWindow!");
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

    // Also fallback dispatch after 1.5, 3.0, and 5.0 seconds in case notification already passed
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_diro_ui();
    });

    // Repeating timer heartbeat to ensure window remains visible and iOSGods stays hidden
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), (uint64_t)(2.0 * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        if (!g_diroWindow || g_diroWindow.hidden) {
            setup_diro_ui();
        } else {
            UIApplication *app = [UIApplication sharedApplication];
            for (UIWindow *w in app.windows) {
                if (w != g_diroWindow) {
                    NSString *cls = NSStringFromClass([w class]);
                    if ([cls containsString:@"ButtonWindow"] || 
                        [cls containsString:@"IGWindow"] || 
                        [cls containsString:@"IGFloating"] || 
                        [cls containsString:@"iOSGods"]) {
                        w.hidden = YES;
                        w.alpha = 0.0;
                        w.userInteractionEnabled = NO;
                    }
                }
            }
        }
    });
    dispatch_resume(timer);
}
