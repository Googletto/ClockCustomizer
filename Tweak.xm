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
//
// NOTE ON APPROACH: earlier versions tried resizing Apple's own time label
// directly, but its frame/width appears to change dynamically (e.g. based
// on wallpaper), which made that approach unreliable — it worked briefly
// after some triggers (like changing wallpaper) and broke again after a
// lock/unlock. This version instead hides Apple's original label and draws
// a completely separate overlay label on top, centered on this view but
// never constrained by its (unstable) width — sidesteps the problem
// entirely rather than fighting it.

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
static CGFloat gTimeYOffset = 0.0;

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
    gTimeYOffset = prefs[@"TimeYOffset"] ? [prefs[@"TimeYOffset"] floatValue] : 0.0;
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
//
// Rather than resizing Apple's own label (its frame/width appears to change
// dynamically, e.g. with wallpaper, which made earlier attempts unreliable),
// we hide it and draw a separate overlay label on top instead, centered on
// this view but with no width restriction of its own.

static char kOverlayLabelKey;
static char kOverlayTimerKey;

%hook CSProminentTimeView

- (UIFont *)primaryFont {
    return TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale);
}

- (void)setPrimaryFont:(UIFont *)primaryFont {
    %orig(TimeFontAtSize(kDefaultTimeFontSize * gTimeSizeScale));
}

- (void)didMoveToWindow {
    %orig;
    if (gDebugLogging) DumpIvarsOnce([self class]);

    if (self.window == nil) {
        NSTimer *t = objc_getAssociatedObject(self, &kOverlayTimerKey);
        [t invalidate];
        objc_setAssociatedObject(self, &kOverlayTimerKey, nil, OBJC_ASSOCIATION_RETAIN);
        return;
    }

    id originalLabel = nil;
    @try { originalLabel = [self valueForKey:@"_textLabel"]; } @catch (__unused NSException *e) {}
    if ([originalLabel respondsToSelector:@selector(setAlpha:)]) {
        [(UIView *)originalLabel setAlpha:0.0];
    }

    self.clipsToBounds = NO;
    if (self.superview) self.superview.clipsToBounds = NO;

    UILabel *overlay = objc_getAssociatedObject(self, &kOverlayLabelKey);
    if (!overlay) {
        overlay = [[UILabel alloc] init];
        overlay.textAlignment = NSTextAlignmentCenter;
        overlay.numberOfLines = 1;
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = [UIColor clearColor];
        overlay.textColor = [UIColor whiteColor];
        @try {
            id origColor = [originalLabel respondsToSelector:@selector(textColor)] ? [originalLabel performSelector:@selector(textColor)] : nil;
            if ([origColor isKindOfClass:[UIColor class]]) overlay.textColor = origColor;
        } @catch (__unused NSException *e) {}
        [self addSubview:overlay];
        objc_setAssociatedObject(self, &kOverlayLabelKey, overlay, OBJC_ASSOCIATION_RETAIN);
    }

    CGFloat baseSize = kDefaultTimeFontSize;
    @try {
        UIFont *existingFont = [originalLabel respondsToSelector:@selector(font)] ? [originalLabel performSelector:@selector(font)] : nil;
        if ([existingFont isKindOfClass:[UIFont class]]) baseSize = existingFont.pointSize;
    } @catch (__unused NSException *e) {}

    __weak __typeof(self) weakSelf = self;
    __weak UILabel *weakOverlay = overlay;

    NSTimer *existingTimer = objc_getAssociatedObject(self, &kOverlayTimerKey);
    [existingTimer invalidate];

    void (^tick)(void) = ^{
        __typeof(self) strongSelf = weakSelf;
        UILabel *ov = weakOverlay;
        if (!strongSelf || !ov) return;

        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = gShowSeconds ? @"HH:mm:ss" : @"HH:mm";
        NSString *timeTemplate = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
        if (timeTemplate && [timeTemplate containsString:@"a"]) {
            df.dateFormat = gShowSeconds ? @"h:mm:ss a" : @"h:mm a";
        }
        NSString *str = [df stringFromDate:[NSDate date]];

        // Cap at the screen width (with a small margin) so it can never
        // overflow off-screen even at the largest Clock Size setting.
        CGFloat desiredSize = baseSize * gTimeSizeScale;
        CGFloat maxWidth = [UIScreen mainScreen].bounds.size.width - 20;
        UIFont *fitted = TimeFontAtSize(desiredSize);
        CGFloat size = desiredSize;
        while (size > 20) {
            CGSize measured = [str sizeWithAttributes:@{NSFontAttributeName: fitted}];
            if (measured.width <= maxWidth) break;
            size -= 2;
            fitted = TimeFontAtSize(size);
        }

        ov.font = fitted;
        ov.text = str;
        CGSize fitSize = [str sizeWithAttributes:@{NSFontAttributeName: fitted}];
        ov.bounds = CGRectMake(0, 0, ceil(fitSize.width) + 4, ceil(fitSize.height) + 4);
        ov.center = CGPointMake(strongSelf.bounds.size.width / 2.0, strongSelf.bounds.size.height / 2.0 + gTimeYOffset);

        // Re-hide the original label and keep our overlay on top every
        // tick, in case something re-shows or re-adds it.
        id label = nil;
        @try { label = [strongSelf valueForKey:@"_textLabel"]; } @catch (__unused NSException *e) {}
        if ([label respondsToSelector:@selector(setAlpha:)]) [(UIView *)label setAlpha:0.0];
        [strongSelf bringSubviewToFront:ov];

        DebugLog(@"Overlay set to: '%@' (font %.1fpt)", str, fitted.pointSize);
    };

    // Always run — not just when Show Seconds is on — so toggling the
    // setting takes effect on the very next tick instead of requiring the
    // clock view to be recreated.
    tick();
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                       repeats:YES
                                                         block:^(NSTimer * _Nonnull t) { tick(); }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self, &kOverlayTimerKey, timer, OBJC_ASSOCIATION_RETAIN);
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
