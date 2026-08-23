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

        // --- Clock size slider ---
        PSSpecifier *sizeGroup = [PSSpecifier groupSpecifierWithName:@"Clock Size"];
        [specifiers addObject:sizeGroup];

        PSSpecifier *sizeSlider = [PSSpecifier
            preferenceSpecifierNamed:@"Clock Size"
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:nil
            cell:PSSliderCell
            edit:nil];
        [sizeSlider setProperty:@"TimeSizeScale" forKey:@"key"];
        [sizeSlider setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
        [sizeSlider setProperty:@(1.0) forKey:@"default"];
        [sizeSlider setProperty:@(0.5) forKey:@"min"];
        [sizeSlider setProperty:@(1.8) forKey:@"max"];
        [sizeSlider setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
        [specifiers addObject:sizeSlider];

        // --- Clock position slider ---
        PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:@"Clock Position"];
        [positionGroup setProperty:@"Slide left for higher up the screen, right for lower."
                            forKey:@"footerText"];
        [specifiers addObject:positionGroup];

        PSSpecifier *positionSlider = [PSSpecifier
            preferenceSpecifierNamed:@"Clock Position"
            target:self
            set:@selector(setPreferenceValue:specifier:)
            get:@selector(readPreferenceValue:)
            detail:nil
            cell:PSSliderCell
            edit:nil];
        [positionSlider setProperty:@"TimeYOffset" forKey:@"key"];
        [positionSlider setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
        [positionSlider setProperty:@(0.0) forKey:@"default"];
        [positionSlider setProperty:@(-100.0) forKey:@"min"];
        [positionSlider setProperty:@(100.0) forKey:@"max"];
        [positionSlider setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
        [specifiers addObject:positionSlider];

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
