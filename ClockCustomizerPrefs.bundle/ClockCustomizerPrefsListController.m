#import "ClockCustomizerPrefsListController.h"
#import <UIKit/UIKit.h>

// Must match kCustomFontsDirectory in Tweak.xm.
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";

@implementation ClockCustomizerPrefsListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray array];

        // --- Group: About ---
        PSSpecifier *groupTop = [PSSpecifier groupSpecifierWithName:@"ClockCustomizer"];
        [groupTop setProperty:[NSString stringWithFormat:
            @"The lock screen shows seconds and picks up its font automatically from the first font "
             "file found in %@ — drop in a .ttf/.otf/.ttc file (via Filza or SSH), then lock/unlock "
             "your phone once.",
             kCustomFontsDirectory]
                        forKey:@"footerText"];
        [specifiers addObject:groupTop];

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

@end
