// ClockCustomizer — Tweak.xm
//
// Target: iOS 17.0–17.3, rootless jailbreak (Dopamine 3 / ellekit)

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>

static NSString * const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.yourname.clockcustomizer.plist";
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";
static NSString * const kDebugLogPath = @"/var/jb/var/mobile/Library/ClockCustomizer/debug.log";

static BOOL gShowSeconds = NO;
static NSString *gFontName = nil;
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

static void DebugLog(NSString *fmt, ...) {
    if (!gDebugLogging) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[ClockCustomizer] %@", msg);

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
        }
    }
    return nil;
}

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

static BOOL IsUIViewSubclass(Class cls) {
    Class c = cls;
    while (c) {
        if (c == [UIView class]) return YES;
        c = class_getSuperclass(c);
    }
    return NO;
}

// Logs every loaded UIView subclass whose name contains the given
// substring — filtered to UIView so we don't drown in thousands of
// unrelated NSLock/os_unfair_lock-type matches on broad terms like "Lock".
static void LogViewClassesContaining(NSString *substring) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if ([name rangeOfString:substring options:NSCaseInsensitiveSearch].location != NSNotFound &&
            IsUIViewSubclass(classes[i])) {
            [matches addObject:name];
        }
    }
    free(classes);
    [matches sortUsingSelector:@selector(compare:)];
    DebugLog(@"---- %lu UIView subclasses matching '%@' ----", (unsigned long)matches.count, substring);
    for (NSString *line in matches) {
        DebugLog(@"  %@", line);
    }
    DebugLog(@"---- end ----");
}

static void RunFullDiagnosticScan(void) {
    Class cls = NSClassFromString(@"SBFLockScreenDateView");
    DebugLog(@"SBFLockScreenDateView is %@.", cls ? @"FOUND" : @"NOT FOUND");
    if (cls) return;
    LogViewClassesContaining(@"Lock");
    LogViewClassesContaining(@"CoverSheet");
    LogViewClassesContaining(@"Dashboard");
}

@interface SBFLockScreenDateView : UIView
@end

%hook SBFLockScreenDateView

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

static void ReloadPrefsAndFonts(void) {
    ReloadPrefs();
    RegisterCustomFonts();
    if (gDebugLogging) {
        DebugLog(@"[Settings changed]");
        RunFullDiagnosticScan();
    }
}

%ctor {
    ReloadPrefsAndFonts();
    if (gDebugLogging) {
        DebugLog(@"ClockCustomizer loaded on iOS %@.", [[UIDevice currentDevice] systemVersion]);
        RunFullDiagnosticScan();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DebugLog(@"---- Rechecking after 5 seconds ----");
            RunFullDiagnosticScan();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DebugLog(@"---- Rechecking after 20 seconds ----");
            RunFullDiagnosticScan();
        });
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     NULL,
                                     (CFNotificationCallback)ReloadPrefsAndFonts,
                                     CFSTR("com.yourname.clockcustomizer/reload"),
                                     NULL,
                                     CFNotificationSuspensionBehaviorDeliverImmediately);
}
