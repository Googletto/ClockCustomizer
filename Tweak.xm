// ClockCustomizer — Tweak.xm
//
// Target: iOS 17.0–17.3, rootless jailbreak (Dopamine 3 / ellekit)
//
// IMPORTANT — READ BEFORE BUILDING:
// The big Lock Screen clock introduced in iOS 16/17 lives in a private
// SpringBoard class from the CoverSheet framework, commonly named
// `CSLockScreenLiveClockView` in 16.x/17.x. Apple has reshuffled internals
// between point releases before, so if this doesn't hook on your exact
// build, see the "FINDING THE RIGHT CLASS" note at the bottom of this file.
//
// Rather than guessing Apple's private date-formatting selectors (which are
// the most likely thing to have shifted across 17.0–17.3), this tweak:
//   1. Hooks the clock view and grabs its time/date UILabels via KVC.
//   2. Applies your chosen font directly to the label.
//   3. Drives its own 1Hz NSTimer to write the time string (with or without
//      seconds) directly onto the label, instead of relying on Apple's
//      private formatter method — this is the most version-resilient way
//      to add a "show seconds" feature.

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>

static NSString * const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.yourname.clockcustomizer.plist";

// Drop .ttf / .otf / .ttc files here (create it via Filza or SSH) and they'll
// show up in the Settings font picker alongside system fonts.
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";

static BOOL gShowSeconds = NO;
static NSString *gFontName = nil;    // e.g. "HelveticaNeue-Thin" — nil = don't override
static BOOL gDebugLogging = NO;

static void EnsureFontsDirectoryExists(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kCustomFontsDirectory]) {
        [fm createDirectoryAtPath:kCustomFontsDirectory
       withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];
    }
}

static void ReloadPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    gShowSeconds = prefs[@"ShowSeconds"] ? [prefs[@"ShowSeconds"] boolValue] : NO;
    gFontName = prefs[@"FontName"];
    gDebugLogging = prefs[@"DebugLogging"] ? [prefs[@"DebugLogging"] boolValue] : NO;
}

static NSString * const kDebugLogPath = @"/var/jb/var/mobile/Library/ClockCustomizer/debug.log";

static void DebugLog(NSString *fmt, ...) {
    if (!gDebugLogging) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[ClockCustomizer] %@", msg);

    // Also write to a plain text file so it can be read with Filza — no
    // computer or syslog tool required.
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], msg];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [kDebugLogPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm fileExistsAtPath:kDebugLogPath]) {
        [fm createFileAtPath:kDebugLogPath contents:nil attributes:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kDebugLogPath];
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// Registers every font file found in kCustomFontsDirectory for THIS process
// only (kCTFontManagerScopeProcess) so [UIFont fontWithName:] can find them
// by their real PostScript name afterward. Safe to call more than once —
// CoreText silently no-ops on already-registered URLs.
static void RegisterCustomFonts(void) {
    EnsureFontsDirectoryExists();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:kCustomFontsDirectory error:nil];
    NSSet *validExtensions = [NSSet setWithObjects:@"ttf", @"otf", @"ttc", nil];

    for (NSString *filename in contents) {
        if (![validExtensions containsObject:filename.pathExtension.lowercaseString]) continue;
        NSString *fullPath = [kCustomFontsDirectory stringByAppendingPathComponent:filename];
        NSURL *url = [NSURL fileURLWithPath:fullPath];
        CFErrorRef error = NULL;
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (error) {
            DebugLog(@"Failed to register custom font %@: %@", filename, error);
            CFRelease(error);
        }
    }
}

// Best-effort ivar names for the time/date labels inside the clock view.
// If hooking fails on your build, dump the class's ivars (see bottom note)
// and update these two arrays.
static NSArray *kTimeLabelIvarCandidates = nil;
static NSArray *kDateLabelIvarCandidates = nil;

static UILabel *FindLabelForIvarNames(id target, NSArray *candidates) {
    for (NSString *name in candidates) {
        @try {
            id value = [target valueForKey:name];
            if ([value isKindOfClass:[UILabel class]]) {
                return (UILabel *)value;
            }
        } @catch (__unused NSException *e) {
            // ivar doesn't exist on this build — try the next candidate
        }
    }
    return nil;
}

// Dumps every ivar name/type on a class — only runs when Debug Logging is
// on, and only once per class.
static void DumpIvarsOnce(Class cls) {
    static NSMutableSet *dumped;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ dumped = [NSMutableSet new]; });
    NSString *clsName = NSStringFromClass(cls);
    if ([dumped containsObject:clsName]) return;
    [dumped addObject:clsName];

    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    DebugLog(@"---- Ivars for %@ ----", clsName);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = ivar_getName(ivars[i]);
        const char *type = ivar_getTypeEncoding(ivars[i]);
        DebugLog(@"  %s  (%s)", name, type);
    }
    free(ivars);
}

// Tell the compiler this private class is a UIView subclass — we don't have
// Apple's real header for it, but this is enough for it to know about
// inherited members like `.window` and `class]`.
@interface CSLockScreenLiveClockView : UIView
@end

%hook CSLockScreenLiveClockView

- (void)didMoveToWindow {
    %orig;
    if (!kTimeLabelIvarCandidates) {
        kTimeLabelIvarCandidates = @[@"_timeLabel", @"timeLabel", @"_clockLabel", @"_timeTextLabel"];
        kDateLabelIvarCandidates = @[@"_dateLabel", @"dateLabel"];
    }
    if (gDebugLogging) DumpIvarsOnce([self class]);

    if (self.window == nil) {
        NSTimer *t = objc_getAssociatedObject(self, @selector(didMoveToWindow));
        [t invalidate];
        objc_setAssociatedObject(self, @selector(didMoveToWindow), nil, OBJC_ASSOCIATION_RETAIN);
        return;
    }

    UILabel *timeLabel = FindLabelForIvarNames(self, kTimeLabelIvarCandidates);
    if (!timeLabel) {
        DebugLog(@"Could not find time label on %@", NSStringFromClass([self class]));
        return;
    }

    if (gFontName.length > 0) {
        UIFont *newFont = [UIFont fontWithName:gFontName size:timeLabel.font.pointSize];
        if (newFont) {
            timeLabel.font = newFont;
        } else {
            DebugLog(@"Font '%@' not found on device.", gFontName);
        }
    }

    __weak UILabel *weakLabel = timeLabel;
    __weak __typeof(self) weakSelf = self;

    NSTimer *existing = objc_getAssociatedObject(self, @selector(didMoveToWindow));
    [existing invalidate];

    void (^tick)(void) = ^{
        UILabel *label = weakLabel;
        __typeof(self) strongSelf = weakSelf;
        if (!label || !strongSelf) return;
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = gShowSeconds ? @"HH:mm:ss" : @"HH:mm";
        if ([NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]] &&
            [[NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]] containsString:@"a"]) {
            df.dateFormat = gShowSeconds ? @"h:mm:ss a" : @"h:mm a";
        }
        label.text = [df stringFromDate:[NSDate date]];
    };

    if (gShowSeconds) {
        tick();
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           repeats:YES
                                                             block:^(NSTimer * _Nonnull t) { tick(); }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(self, @selector(didMoveToWindow), timer, OBJC_ASSOCIATION_RETAIN);
    }
}

%end

// Scans every Objective-C class currently loaded in this process and logs
// any whose name contains the given substring — used to find the real
// private class name for the lock screen clock on this specific device/build.
static void LogClassesContaining(NSString *substring) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:substring options:NSCaseInsensitiveSearch].location != NSNotFound) {
            Class superclass = class_getSuperclass(classes[i]);
            [matches addObject:[NSString stringWithFormat:@"%@  (superclass: %@)",
                                 name, superclass ? NSStringFromClass(superclass) : @"none"]];
        }
    }
    free(classes);
    [matches sortUsingSelector:@selector(compare:)];
    DebugLog(@"---- %lu classes matching '%@' ----", (unsigned long)matches.count, substring);
    for (NSString *line in matches) {
        DebugLog(@"  %@", line);
    }
    DebugLog(@"---- end of matches ----");
}

static void ReloadPrefsAndFonts(void) {
    ReloadPrefs();
    RegisterCustomFonts();
    if (gDebugLogging) {
        Class cls = NSClassFromString(@"CSLockScreenLiveClockView");
        DebugLog(@"[Settings changed] CSLockScreenLiveClockView is %@.", cls ? @"FOUND" : @"NOT FOUND");
        if (!cls) LogClassesContaining(@"Clock");
    }
}

%ctor {
    ReloadPrefsAndFonts();
    if (gDebugLogging) {
        DebugLog(@"ClockCustomizer loaded on iOS %@.", [[UIDevice currentDevice] systemVersion]);
        void (^checkAndMaybeScan)(void) = ^{
            Class cls = NSClassFromString(@"CSLockScreenLiveClockView");
            DebugLog(@"CSLockScreenLiveClockView is %@.", cls ? @"FOUND" : @"still NOT FOUND");
            if (!cls) LogClassesContaining(@"Clock");
        };
        checkAndMaybeScan();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DebugLog(@"---- Rechecking after 5 seconds ----");
            checkAndMaybeScan();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DebugLog(@"---- Rechecking after 20 seconds ----");
            checkAndMaybeScan();
        });
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     NULL,
                                     (CFNotificationCallback)ReloadPrefsAndFonts,
                                     CFSTR("com.yourname.clockcustomizer/reload"),
                                     NULL,
                                     CFNotificationSuspensionBehaviorDeliverImmediately);
}
