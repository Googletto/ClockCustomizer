#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <Preferences/Preferences.h>
#import <logos/logos.h>

// ============================================
// PREFERENCES HELPER
// ============================================
static NSDictionary *getPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.googletto.clockcustomizer.plist"];
    if (!prefs) {
        // Fallback default values
        prefs = @{
            @"fontName": @"Helvetica",
            @"fontSize": @(80),
            @"timeXOffset": @(0),
            @"timeYOffset": @(0),
            @"dateXOffset": @(0),
            @"dateYOffset": @(20),
            @"showSeconds": @(NO)
        };
    }
    return prefs;
}

// ============================================
// BULLETPROOF FONT LOADER (NO REGISTRATION)
// ============================================
static UIFont *loadFontFromPath(NSString *fontPath, CGFloat size) {
    // 1. Try direct file read
    NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
    if (!fontData) {
        NSLog(@"ClockCustomizer: Font file NOT FOUND at %@", fontPath);
        return nil;
    }
    
    // 2. Create CoreText font directly from data (bypasses sandbox)
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    if (!cgFont) {
        CGDataProviderRelease(provider);
        NSLog(@"ClockCustomizer: Failed to create CGFont");
        return nil;
    }
    
    CTFontRef ctFont = CTFontCreateWithGraphicsFont(cgFont, size, NULL, NULL);
    CGFontRelease(cgFont);
    CGDataProviderRelease(provider);
    
    // Bridge to UIFont (safe for attributed strings)
    return (__bridge_transfer UIFont *)ctFont;
}

// ============================================
// FILE SEARCHER (LOOKS IN MULTIPLE PATHS)
// ============================================
static NSString *findFontFile(NSString *fontName) {
    // If it's a system font name (e.g., "Helvetica"), return nil – we'll use system font
    NSArray *systemFonts = @[@"Helvetica", @"Arial", @"Times New Roman", @"Courier", @"Georgia", @"Verdana"];
    if ([systemFonts containsObject:fontName]) {
        return nil;
    }
    
    // If the user entered a full path, use it directly
    if ([fontName hasPrefix:@"/"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:fontName]) {
            return fontName;
        }
        return nil;
    }
    
    // Search in common rootless paths
    NSArray *searchPaths = @[
        @"/var/jb/Library/Fonts/ClockCustomizer/",
        @"/var/mobile/Library/ClockCustomizer/Fonts/",
        @"/var/jb/Library/Fonts/"
    ];
    
    for (NSString *basePath in searchPaths) {
        NSString *fullPath = [basePath stringByAppendingPathComponent:fontName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            NSLog(@"ClockCustomizer: Found font at %@", fullPath);
            return fullPath;
        }
    }
    
    // Try appending .ttf or .otf if the user didn't specify
    for (NSString *basePath in searchPaths) {
        NSString *pathWithExt = [basePath stringByAppendingPathComponent:[fontName stringByAppendingString:@".ttf"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pathWithExt]) {
            NSLog(@"ClockCustomizer: Found font (with .ttf) at %@", pathWithExt);
            return pathWithExt;
        }
        pathWithExt = [basePath stringByAppendingPathComponent:[fontName stringByAppendingString:@".otf"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pathWithExt]) {
            NSLog(@"ClockCustomizer: Found font (with .otf) at %@", pathWithExt);
            return pathWithExt;
        }
    }
    
    return nil;
}

// ============================================
// OVERLAY VIEW – DRAWS CUSTOM CLOCK + DATE
// ============================================
@interface ClockCustomizerOverlay : UIView
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) NSDictionary *prefs;
- (void)updateTime;
@end

@implementation ClockCustomizerOverlay

- (instancetype)initWithFrame:(CGRect)frame prefs:(NSDictionary *)prefs {
    self = [super initWithFrame:frame];
    if (self) {
        self.prefs = prefs;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        
        // Time label
        self.timeLabel = [[UILabel alloc] init];
        self.timeLabel.textAlignment = NSTextAlignmentCenter;
        self.timeLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:self.timeLabel];
        
        // Date label
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.textAlignment = NSTextAlignmentCenter;
        self.dateLabel.backgroundColor = [UIColor clearColor];
        self.dateLabel.font = [UIFont systemFontOfSize:16];
        self.dateLabel.textColor = [UIColor whiteColor];
        [self addSubview:self.dateLabel];
        
        // Start timer for seconds if enabled
        if ([prefs[@"showSeconds"] boolValue]) {
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTime) userInfo:nil repeats:YES];
        }
        
        [self updateTime];
    }
    return self;
}

- (void)updateTime {
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setDateFormat:@"hh:mm"]; // Base time
    
    if ([self.prefs[@"showSeconds"] boolValue]) {
        [timeFormatter setDateFormat:@"hh:mm:ss"];
    }
    
    NSString *timeString = [timeFormatter stringFromDate:[NSDate date]];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"EEEE, MMM d"];
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    
    // ---- LOAD FONT ----
    UIFont *timeFont = nil;
    NSString *fontName = self.prefs[@"fontName"];
    CGFloat fontSize = [self.prefs[@"fontSize"] floatValue] ?: 80.0;
    
    if (fontName && fontName.length > 0) {
        NSString *fontPath = findFontFile(fontName);
        if (fontPath) {
            timeFont = loadFontFromPath(fontPath, fontSize);
            if (timeFont) {
                NSLog(@"ClockCustomizer: Successfully loaded custom font from %@", fontPath);
            } else {
                NSLog(@"ClockCustomizer: Failed to load font from path, falling back to system");
            }
        } else {
            // Check if it's a system font name (e.g., "Helvetica-Bold")
            timeFont = [UIFont fontWithName:fontName size:fontSize];
            if (timeFont) {
                NSLog(@"ClockCustomizer: Using system font: %@", fontName);
            } else {
                NSLog(@"ClockCustomizer: Font '%@' not found as system font, using default", fontName);
            }
        }
    }
    
    // Fallback to system font if custom failed
    if (!timeFont) {
        timeFont = [UIFont systemFontOfSize:fontSize weight:UIFontWeightThin];
    }
    
    // Apply attributed string (so font applies perfectly)
    NSDictionary *attributes = @{
        NSFontAttributeName: timeFont,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSKernAttributeName: @(1.0) // slight letter spacing
    };
    
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:timeString attributes:attributes];
    self.timeLabel.attributedText = attrString;
    
    // Date label
    self.dateLabel.text = dateString;
    
    // Layout (position based on prefs)
    CGFloat timeX = [self.prefs[@"timeXOffset"] floatValue];
    CGFloat timeY = [self.prefs[@"timeYOffset"] floatValue];
    CGFloat dateX = [self.prefs[@"dateXOffset"] floatValue];
    CGFloat dateY = [self.prefs[@"dateYOffset"] floatValue];
    
    // Size the labels
    [self.timeLabel sizeToFit];
    [self.dateLabel sizeToFit];
    
    // Center them relative to self, with offsets
    CGSize timeSize = self.timeLabel.frame.size;
    CGSize dateSize = self.dateLabel.frame.size;
    
    self.timeLabel.frame = CGRectMake(
        (self.bounds.size.width - timeSize.width) / 2 + timeX,
        (self.bounds.size.height - timeSize.height - dateSize.height - 10) / 2 + timeY,
        timeSize.width,
        timeSize.height
    );
    
    self.dateLabel.frame = CGRectMake(
        (self.bounds.size.width - dateSize.width) / 2 + dateX,
        CGRectGetMaxY(self.timeLabel.frame) + 10 + dateY,
        dateSize.width,
        dateSize.height
    );
}

@end

// ============================================
// THE HOOK – INJECT OVERLAY INTO LOCK SCREEN
// ============================================
%hook SBFLockScreenDateView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        // Hide the original time and date labels
        // iOS 17 uses _timeLabel and _dateLabel (or similar)
        [self setValue:@(NO) forKey:@"showsTime"]; // Try to hide via property
        [[self valueForKey:@"_timeLabel"] setHidden:YES];
        [[self valueForKey:@"_dateLabel"] setHidden:YES];
        
        // Add our custom overlay
        NSDictionary *prefs = getPrefs();
        ClockCustomizerOverlay *overlay = [[ClockCustomizerOverlay alloc] initWithFrame:self.bounds prefs:prefs];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:overlay];
        
        NSLog(@"ClockCustomizer: Overlay injected successfully!");
    }
    return self;
}

%end

// ============================================
// CONSTRUCTOR
// ============================================
%ctor {
    NSLog(@"ClockCustomizer: Tweak loaded!");
}
