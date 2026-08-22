// ClockCustomizer — Tweak.xm
//
// Target: iOS 17.0–17.3, rootless jailbreak (Dopamine 3 / ellekit)
//
// This build's approach to the font is based on the technique documented by
// NightwindDev/old-lockscreen (https://github.com/NightwindDev/old-lockscreen):
// SBFLockScreenDateView exposes -customTimeFont / -setCustomTimeFont: as the
// real, supported override point for the lock screen clock's font — far more
// reliable than reaching into a private label ivar directly.

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

// Returns our chosen font at the given size, or nil if no custom font is set
// (in which case the caller should fall back to the original/system font).
static UIFont *CustomTimeFontOrNil(CGFloat sizeHint) {
    if (gFontName.length == 0) return nil;
    CGFloat size = sizeHint > 0 ? sizeHint : 80;
    return [UIFont fontWithName:gFontName size:size];
}

// Dumps every method on a class by name, WITHOUT needing a live instance —
// works immediately at load time, no lock/unlock cycle required.
static void DumpClassMethodsIfExists(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        DebugLog(@"Class %@ not found.", className);
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    DebugLog(@"---- %lu methods on class %@ ----", (unsigned long)names.count, className);
    for (NSString *n in names) {
        DebugLog(@"  %@", n);
    }
    DebugLog(@"---- end ----");
}

static BOOL IsUIViewSubclass(Class cls) {
    Class c = cls;
    while (c) {
        if (c == [UIView class]) return YES;
        c = class_getSuperclass(c);
    }
    return NO;
}

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

    LogViewClassesContaining(@"Prominent");
    DumpClassMethodsIfExists(@"CSProminentTimeView");
    DumpClassMethodsIfExists(@"CSProminentTextElementView");
    DumpClassMethodsIfExists(@"CSProminentSubtitleDateView");
}

@interface SBFLockScreenDateView : UIView
@end

%hook SBFLockScreenDateView

- (UIFont *)customTimeFont {
    UIFont *orig = %orig;
    UIFont *custom = CustomTimeFontOrNil(orig ? orig.pointSize : 80);
    return custom ?: orig;
}

- (void)setCustomTimeFont:(UIFont *)customTimeFont {
    UIFont *custom = CustomTimeFontOrNil(customTimeFont ? customTimeFont.pointSize : 80);
    %orig(custom ?: customTimeFont);
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
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     NULL,
                                     (CFNotificationCallback)ReloadPrefsAndFonts,
                                     CFSTR("com.yourname.clockcustomizer/reload"),
                                     NULL,
                                     CFNotificationSuspensionBehaviorDeliverImmediately);
}
