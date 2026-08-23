// ClockCustomizer — Tweak.xm
//
// Target: iOS 17.0–17.3, rootless jailbreak (Dopamine 3 / ellekit)
//
// This is a fork/extension of NightwindDev/old-lockscreen
// (https://github.com/NightwindDev/old-lockscreen, MIT licensed), which
// restores the iOS 15-style lock screen clock layout on iOS 16/17. That
// project's hooks are the proven, working baseline on this device — this
// file keeps its layout/positioning fixes and adds a configurable font and
// a "show seconds" feature on top.
//
// IMPORTANT: this REPLACES NightwindDev's original tweak rather than
// running alongside it — installing this while the original is also
// installed means two tweaks fighting over the same private methods.
// Uninstall the original before installing this one.

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>

#define kSubtitlePadding 102
#define kDefaultTimeFontSize 80
#define kDateFontSize 22

static NSString * const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.yourname.clockcustomizer.plist";
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";
static NSString * const kDebugLogPath = @"/var/jb/var/mobile/Library/ClockCustomizer/debug.log";

static BOOL gShowSeconds = YES; // always on — no longer a toggle
static NSString *gFontName = nil;
static BOOL gDebugLogging = NO;
static NSString *gRegisteredCustomFontName = nil; // real PostScript name, auto-detected on registration
static CGFloat gTimeSizeScale = 1.0;

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
    gFontName = prefs[@"FontName"];
    gDebugLogging = prefs[@"DebugLogging"] ? [prefs[@"DebugLogging"] boolValue] : NO;
    gTimeSizeScale = prefs[@"TimeSizeScale"] ? [prefs[@"TimeSizeScale"] floatValue] : 1.0;
    if (gTimeSizeScale <= 0) gTimeSizeScale = 1.0;
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

        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        DebugLog(@"Font file %@ is %@ bytes", filename, attrs[NSFileSize]);

        CFErrorRef error = NULL;
        BOOL ok = CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (!ok || error) {
            DebugLog(@"Failed to register custom font %@: %@", filename, error);
            if (error) CFRelease(error);
            continue;
        }

        // Look up the real PostScript name so we can pass it to
        // +[UIFont fontWithName:] later — it may not match the filename.
        CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
        if (descriptors && CFArrayGetCount(descriptors) > 0) {
            CTFontDescriptorRef desc = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors, 0);
            CFStringRef psNameRef = (CFStringRef)CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute);
            if (psNameRef) {
                gRegisteredCustomFontName = (__bridge_transfer NSString *)psNameRef;
                DebugLog(@"Registered %@ as font name: %@", filename, gRegisteredCustomFontName);
            }
        }
        if (descriptors) CFRelease(descriptors);
    }
}

// Our chosen font at the given size if one is set, otherwise the classic
// thin system font old-lockscreen used by default.
static UIFont *TimeFontAtSize(CGFloat size) {
    if (gRegisteredCustomFontName.length > 0) {
        UIFont *custom = [UIFont fontWithName:gRegisteredCustomFontName size:size];
        if (custom) return custom;
    }
    if (gFontName.length > 0) {
        UIFont *custom = [UIFont fontWithName:gFontName size:size];
        if (custom) return custom;
    }
    return [UIFont systemFontOfSize:size weight:UIFontWeightThin];
}

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

// --- Interfaces for the private classes involved (from old-lockscreen) ---

@interface CSProminentSubtitleDateView : UIView
@end
@interface CSProminentEmptyElementView : UIView
@end
@interface CSProminentTextElementView : UIView
@end
@interface CSProminentTimeView : CSProminentTextElementView
@end
@interface SBFLockScreenDateView : UIView
@end

// --- Clock font (the class that owns the big time display) ---

%hook SBFLockScreenDateView

+ (UIFont *)timeFont {
    return TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale);
}

- (UIFont *)customTimeFont {
    return TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale);
}

- (void)setCustomTimeFont:(UIFont *)customTimeFont {
    %orig(TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale));
}

%end

// --- Time text itself ---

%hook CSProminentTimeView

- (CGRect)frame {
    CGRect orig = %orig;
    return CGRectMake(orig.origin.x, 5, orig.size.width, orig.size.height);
}

- (void)setFrame:(CGRect)frame {
    %orig(CGRectMake(frame.origin.x, 5, frame.size.width, frame.size.height));
}

- (UIFont *)primaryFont {
    return TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale);
}

- (void)setPrimaryFont:(UIFont *)primaryFont {
    %orig(TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale));
}

// Mirrors CSProminentSubtitleDateView's proven _textLabel technique below —
// CSProminentTimeView is a sibling subclass of the same base class, so it
// likely has the same ivar. If Debug Logging is on and it's missing, we log
// diagnostics instead of guessing further.
- (void)didMoveToWindow {
    %orig;
    if (gDebugLogging) DumpIvarsOnce([self class]);

    if (self.window == nil) {
        NSTimer *t = objc_getAssociatedObject(self, @selector(didMoveToWindow));
        [t invalidate];
        objc_setAssociatedObject(self, @selector(didMoveToWindow), nil, OBJC_ASSOCIATION_RETAIN);
        return;
    }

    id textLabel = nil;
    @try { textLabel = [self valueForKey:@"_textLabel"]; } @catch (__unused NSException *e) {}

    BOOL usable = [textLabel respondsToSelector:@selector(setText:)];
    if (!usable) {
        DebugLog(@"CSProminentTimeView _textLabel not usable (class: %@)",
                 textLabel ? NSStringFromClass([textLabel class]) : @"nil");
        if (gDebugLogging) DumpClassMethodsIfExists(NSStringFromClass([self class]));
        return;
    }

    // Apply our font directly to the same object we already know works for
    // text, rather than relying on primaryFont/customTimeFont, which don't
    // seem to affect actual rendering on this build.
    CGFloat baseSize = kDefaultTimeFontSize;
    @try {
        UIFont *existingFont = [textLabel respondsToSelector:@selector(font)] ? [textLabel performSelector:@selector(font)] : nil;
        if ([existingFont isKindOfClass:[UIFont class]]) baseSize = existingFont.pointSize;
    } @catch (__unused NSException *e) {}

    // Prevent the label from shrinking the font when "HH:mm:ss" is longer
    // than "HH:mm".
    if ([textLabel respondsToSelector:@selector(setAdjustsFontSizeToFitWidth:)]) {
        [textLabel setAdjustsFontSizeToFitWidth:NO];
    }
    if ([textLabel respondsToSelector:@selector(setMinimumScaleFactor:)]) {
        [textLabel setMinimumScaleFactor:1.0];
    }
    if ([textLabel respondsToSelector:@selector(setNumberOfLines:)]) {
        [textLabel setNumberOfLines:1];
    }
    if ([textLabel respondsToSelector:@selector(setTextAlignment:)]) {
        [textLabel setTextAlignment:NSTextAlignmentCenter];
    }

    __weak id weakLabel = textLabel;
    __weak __typeof(self) weakSelf = self;

    NSTimer *existing = objc_getAssociatedObject(self, @selector(didMoveToWindow));
    [existing invalidate];

    void (^tick)(void) = ^{
        id label = weakLabel;
        __typeof(self) strongSelf = weakSelf;
        if (!label || !strongSelf) return;
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = gShowSeconds ? @"HH:mm:ss" : @"HH:mm";
        NSString *timeTemplate = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
        if (timeTemplate && [timeTemplate containsString:@"a"]) {
            df.dateFormat = gShowSeconds ? @"h:mm:ss a" : @"h:mm a";
        }
        NSString *str = [df stringFromDate:[NSDate date]];

        // Measure the string against the label's actual current width and
        // back off font size only as much as needed to make it fit — this
        // adapts correctly across the whole Clock Size slider range instead
        // of relying on one fixed guessed shrink factor.
        CGFloat desiredSize = baseSize * gTimeSizeScale;
        CGFloat availableWidth = [label respondsToSelector:@selector(bounds)] ? ((UIView *)label).bounds.size.width : 0;
        UIFont *fitted = TimeFontAtSize(desiredSize);
        if (availableWidth > 10) {
            CGFloat size = desiredSize;
            while (size > 20) {
                CGSize measured = [str sizeWithAttributes:@{NSFontAttributeName: fitted}];
                if (measured.width <= availableWidth) break;
                size -= 2;
                fitted = TimeFontAtSize(size);
            }
        }
        [label setFont:fitted];

        DebugLog(@"Setting time text to: '%@' (len %lu, font %.1fpt)", str, (unsigned long)str.length, fitted.pointSize);
        [label setText:str];
    };

    // Always run — not just when Show Seconds is on — so toggling the
    // setting takes effect on the very next tick instead of requiring the
    // clock view to be recreated (which doesn't reliably happen on every
    // lock/unlock). Interval is short to minimize the flicker window when
    // the system briefly reasserts its own text during the unlock animation.
    tick();
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                       repeats:YES
                                                         block:^(NSTimer * _Nonnull t) { tick(); }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self, @selector(didMoveToWindow), timer, OBJC_ASSOCIATION_RETAIN);
}

%end

// --- Date subtitle (e.g. "Tuesday, August 22") ---

%hook CSProminentSubtitleDateView

- (CGRect)frame {
    CGRect orig = %orig;
    return CGRectMake(orig.origin.x, kSubtitlePadding, orig.size.width, orig.size.height);
}

- (void)setFrame:(CGRect)frame {
    %orig(CGRectMake(frame.origin.x, kSubtitlePadding, frame.size.width, frame.size.height));
}

- (void)didMoveToWindow {
    %orig;
    UILabel *textLabel = [self valueForKey:@"_textLabel"];
    [textLabel setFont:[UIFont systemFontOfSize:kDateFontSize weight:UIFontWeightRegular]];
}

%end

// --- Miscellaneous elements around the clock (battery charging text, etc.) ---

%hook CSProminentEmptyElementView

- (CGRect)frame {
    CGRect orig = %orig;
    return CGRectMake(orig.origin.x, kSubtitlePadding, orig.size.width, orig.size.height);
}

- (void)setFrame:(CGRect)frame {
    %orig(CGRectMake(frame.origin.x, kSubtitlePadding, frame.size.width, frame.size.height));
}

%end

%hook CSProminentTextElementView

- (CGRect)frame {
    if (![self isKindOfClass:%c(CSProminentTimeView)]) {
        CGRect orig = %orig;
        return CGRectMake(orig.origin.x, kSubtitlePadding, orig.size.width, orig.size.height);
    }
    return %orig;
}

- (void)setFrame:(CGRect)frame {
    if (![self isKindOfClass:%c(CSProminentTimeView)]) {
        %orig(CGRectMake(frame.origin.x, kSubtitlePadding, frame.size.width, frame.size.height));
    } else {
        %orig;
    }
}

%end

static void ReloadPrefsAndFonts(void) {
    ReloadPrefs();
    RegisterCustomFonts();
}

%ctor {
    ReloadPrefsAndFonts();
    if (gDebugLogging) {
        DebugLog(@"ClockCustomizer (old-lockscreen fork) loaded on iOS %@.", [[UIDevice currentDevice] systemVersion]);
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     NULL,
                                     (CFNotificationCallback)ReloadPrefsAndFonts,
                                     CFSTR("com.yourname.clockcustomizer/reload"),
                                     NULL,
                                     CFNotificationSuspensionBehaviorDeliverImmediately);
}
