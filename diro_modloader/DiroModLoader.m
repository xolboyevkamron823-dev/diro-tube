#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include "fishhook.h"

static int (*orig_open)(const char *path, int oflag, ...) = NULL;
static int (*orig_open_nocancel)(const char *path, int oflag, ...) = NULL;
static FILE *(*orig_fopen)(const char *filename, const char *mode) = NULL;
static int (*orig_stat)(const char *path, struct stat *buf) = NULL;
static int (*orig_lstat)(const char *path, struct stat *buf) = NULL;
static int (*orig_access)(const char *path, int amode) = NULL;

static NSString *g_docsDir = nil;

static void init_docs_dir(void) {
    if (!g_docsDir) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            g_docsDir = paths[0];
            NSLog(@"[DiroModLoader] Documents directory: %@", g_docsDir);
        }
    }
}

static const char *get_override_path(const char *path) {
    if (!path) return path;
    init_docs_dir();
    if (!g_docsDir) return path;

    // Check if path refers to gta3.img
    if (strcasestr(path, "gta3.img") != NULL) {
        // Option 1: Documents/texdb/gta3.img
        NSString *p1 = [g_docsDir stringByAppendingPathComponent:@"texdb/gta3.img"];
        if (access([p1 UTF8String], R_OK) == 0) {
            NSLog(@"[DiroModLoader] Overriding gta3.img with: %@", p1);
            return [p1 UTF8String];
        }
        // Option 2: Documents/gta3.img
        NSString *p2 = [g_docsDir stringByAppendingPathComponent:@"gta3.img"];
        if (access([p2 UTF8String], R_OK) == 0) {
            NSLog(@"[DiroModLoader] Overriding gta3.img with: %@", p2);
            return [p2 UTF8String];
        }
    }

    // Support custom data files (carcols.dat, handling.cfg) in Documents/data/
    if (strcasestr(path, "handling.cfg") != NULL) {
        NSString *p = [g_docsDir stringByAppendingPathComponent:@"data/handling.cfg"];
        if (access([p UTF8String], R_OK) == 0) return [p UTF8String];
    }
    if (strcasestr(path, "carcols.dat") != NULL) {
        NSString *p = [g_docsDir stringByAppendingPathComponent:@"data/carcols.dat"];
        if (access([p UTF8String], R_OK) == 0) return [p UTF8String];
    }

    return path;
}

static int hooked_open(const char *path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list args;
        va_start(args, oflag);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    const char *target = get_override_path(path);
    if (orig_open) {
        return orig_open(target, oflag, mode);
    }
    return open(target, oflag, mode);
}

static int hooked_open_nocancel(const char *path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list args;
        va_start(args, oflag);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    const char *target = get_override_path(path);
    if (orig_open_nocancel) {
        return orig_open_nocancel(target, oflag, mode);
    }
    return open(target, oflag, mode);
}

static FILE *hooked_fopen(const char *filename, const char *mode) {
    const char *target = get_override_path(filename);
    if (orig_fopen) {
        return orig_fopen(target, mode);
    }
    return fopen(target, mode);
}

static int hooked_stat(const char *path, struct stat *buf) {
    const char *target = get_override_path(path);
    if (orig_stat) return orig_stat(target, buf);
    return stat(target, buf);
}

static int hooked_lstat(const char *path, struct stat *buf) {
    const char *target = get_override_path(path);
    if (orig_lstat) return orig_lstat(target, buf);
    return lstat(target, buf);
}

static int hooked_access(const char *path, int amode) {
    const char *target = get_override_path(path);
    if (orig_access) return orig_access(target, amode);
    return access(target, amode);
}

// Dyld interpose table
#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
            __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(hooked_open, open);
DYLD_INTERPOSE(hooked_fopen, fopen);
DYLD_INTERPOSE(hooked_stat, stat);
DYLD_INTERPOSE(hooked_lstat, lstat);
DYLD_INTERPOSE(hooked_access, access);

__attribute__((constructor))
static void init_modloader(void) {
    @autoreleasepool {
        init_docs_dir();
        NSLog(@"[DiroModLoader] Starting GTA SA iOS Dynamic ModLoader...");

        // 1. Fishhook dynamic rebinding
        rebind_symbols((struct rebinding[]){
            {"open", (void*)hooked_open, (void**)&orig_open},
            {"open$NOCANCEL", (void*)hooked_open_nocancel, (void**)&orig_open_nocancel},
            {"fopen", (void*)hooked_fopen, (void**)&orig_fopen},
            {"stat", (void*)hooked_stat, (void**)&orig_stat},
            {"lstat", (void*)hooked_lstat, (void**)&orig_lstat},
            {"access", (void*)hooked_access, (void**)&orig_access}
        }, 6);

        // 2. CydiaSubstrate fallback if present
        void (*MSHookFunction)(void *symbol, void *replace, void **result) = (void (*)(void*, void*, void**))dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (MSHookFunction) {
            void *hOpen = dlsym(RTLD_DEFAULT, "open");
            if (hOpen && !orig_open) MSHookFunction(hOpen, (void*)hooked_open, (void**)&orig_open);

            void *hFopen = dlsym(RTLD_DEFAULT, "fopen");
            if (hFopen && !orig_fopen) MSHookFunction(hFopen, (void*)hooked_fopen, (void**)&orig_fopen);
        }

        NSLog(@"[DiroModLoader] Hooks successfully installed!");
    }
}
