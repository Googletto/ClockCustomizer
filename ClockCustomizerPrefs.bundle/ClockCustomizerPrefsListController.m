#import "ClockCustomizerPrefsListController.h"
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

// Must match kCustomFontsDirectory in Tweak.xm.
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";

@interface ClockCustomizerPrefsListController ()
@property (nonatomic, strong) NSArray<NSString *> *customFontValues; // real PostScript names, for storing in prefs
@property (nonatomic, strong) NSArray<NSString *> *customFontTitles; // "Filename (Custom)", for display
@end

@implementation ClockCustomizerPrefsListController

// Creates the folder if missing, registers every font file inside it for
// THIS process (so we can read back its real display name), and fills in
// customFontValues / customFontTitles.
- (void)scanAndRegisterCustomFonts {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kCustomFontsDirectory]) {
        [fm createDirectoryAtPath:kCustomFontsDirectory
       withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];
    }

    NSMutableArray *values = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    NSSet *validExtensions = [NSSet setWithObjects:@"ttf", @"otf", @"ttc", nil];

    NSArray *contents = [[fm contentsOfDirectoryAtPath:kCustomFontsDirectory error:nil]
                          sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *filename in contents) {
        if (![validExtensions containsObject:filename.pathExtension.lowercaseString]) continue;

        NSString *fullPath = [kCustomFontsDirectory stringByAppendingPathComponent:filename];
        NSURL *url = [NSURL fileURLWithPath:fullPath];

        CFErrorRef error = NULL;
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (error) CFRelease(error);

        CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
        if (!descriptors) continue;

        for (CFIndex i = 0; i < CFArrayGetCount(descriptors); i++) {
            CTFontDescriptorRef desc = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors, i);
            CFStringRef psNameRef = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute);
            if (!psNameRef) continue;
            NSString *psName = (__bridge_transfer NSString *)psNameRef;
            [values addObject:psName];
            [titles addObject:[NSString stringWithFormat:@"%@ (Custom)", filename.stringByDeletingPathExtension]];
        }
        CFRelease(descriptors);
    }

    self.customFontValues = values;
    self.customFontTitles = titles;
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        [self scanAndRegisterCustomFonts];
        NSMutableArray *specifiers = [NSMutableArray array];

        // --- Group: About ---
        PSSpecifier *groupTop = [PSSpecifier groupSpecifierWithName:@"ClockCustomizer"];
        [specifiers addObject:groupTop];

        // --- Show Seconds toggle ---
        PSSpecifier *secondsSwitch = [PSSpecifier
            preferenceSpecifierNamed:@"Show Seconds"
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:nil
            cell:PSSwitchCell
            edit:nil];
        [secondsSwitch setProperty:@"ShowSeconds" forKey:@"key"];
        [secondsSwitch setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
        [secondsSwitch setProperty:@(NO) forKey:@"default"];
        [secondsSwitch setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
        [specifiers addObject:secondsSwitch];

        // --- Group: Font ---
        PSSpecifier *groupFont = [PSSpecifier groupSpecifierWithName:@"Lock Screen Clock Font"];
        [groupFont setProperty:[NSString stringWithFormat:
            @"Custom fonts are picked up automatically from %@ — drop in .ttf/.otf/.ttc files "
             "(via Filza or SSH) and reopen this page. A lock/unlock cycle applies a new font "
             "to the lock screen.", kCustomFontsDirectory]
                          forKey:@"footerText"];
        [specifiers addObject:groupFont];

        NSMutableArray *fontValues = [NSMutableArray arrayWithArray:self.customFontValues];
        NSMutableArray *fontTitles = [NSMutableArray arrayWithArray:self.customFontTitles];
        [fontValues addObjectsFromArray:[self installedFontNames]];
        [fontTitles addObjectsFromArray:[self installedFontDisplayNames]];

        PSSpecifier *fontPicker = [PSSpecifier
            preferenceSpecifierNamed:@"Font"
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:[NSClassFromString(@"PSListItemsController") class]
            cell:PSLinkListCell
            edit:nil];
        [fontPicker setProperty:@"FontName" forKey:@"key"];
        [fontPicker setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
        [fontPicker setProperty:@"HelveticaNeue-Thin" forKey:@"default"];
        [fontPicker setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
        [fontPicker setProperty:fontValues forKey:@"values"];
        [fontPicker setProperty:fontTitles forKey:@"titles"];
        [specifiers addObject:fontPicker];

        // --- Group: Debug ---
        PSSpecifier *groupDebug = [PSSpecifier groupSpecifierWithName:@"Troubleshooting"];
        [groupDebug setProperty:@"Only needed if the clock isn't updating — see Tweak.xm comments for how to read the log."
                          forKey:@"footerText"];
        [specifiers addObject:groupDebug];

        PSSpecifier *debugSwitch = [PSSpecifier
            preferenceSpecifierNamed:@"Debug Logging"
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:nil
            cell:PSSwitchCell
            edit:nil];
        [debugSwitch setProperty:@"DebugLogging" forKey:@"key"];
        [debugSwitch setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
        [debugSwitch setProperty:@(NO) forKey:@"default"];
        [debugSwitch setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
        [specifiers addObject:debugSwitch];

        _specifiers = specifiers;
    }
    return _specifiers;
}

// Every font family/name installed on-device (system fonts + any you've
// sideloaded via a font-installer tweak) — shown so the user can pick one
// for the lock screen clock.
- (NSArray *)installedFontNames {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *family in [UIFont familyNames]) {
        for (NSString *name in [UIFont fontNamesForFamilyName:family]) {
            [names addObject:name];
        }
    }
    [names sortUsingSelector:@selector(compare:)];
    return names;
}

- (NSArray *)installedFontDisplayNames {
    return [self installedFontNames];
}

@end
