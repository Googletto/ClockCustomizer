#import "ClockCustomizerPrefsListController.h"
#import <UIKit/UIKit.h>

// Must match kCustomFontsDirectory in Tweak.xm.
static NSString * const kCustomFontsDirectory = @"/var/jb/var/mobile/Library/ClockCustomizer/Fonts";

@implementation ClockCustomizerPrefsListController

- (PSSpecifier *)sliderNamed:(NSString *)name key:(NSString *)key
                     minimum:(double)minimum maximum:(double)maximum
                     default:(double)defaultValue {
    PSSpecifier *slider = [PSSpecifier
        preferenceSpecifierNamed:name
        target:self
        set:@selector(setPreferenceValue:specifier:)
        get:@selector(readPreferenceValue:)
        detail:nil
        cell:PSSliderCell
        edit:nil];
    [slider setProperty:key forKey:@"key"];
    [slider setProperty:@"com.yourname.clockcustomizer" forKey:@"defaults"];
    [slider setProperty:@(defaultValue) forKey:@"default"];
    [slider setProperty:@(minimum) forKey:@"min"];
    [slider setProperty:@(maximum) forKey:@"max"];
    [slider setProperty:@"com.yourname.clockcustomizer/reload" forKey:@"PostNotification"];
    return slider;
}

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
        [specifiers addObject:[self sliderNamed:@"Clock Size" key:@"TimeSizeScale"
                                         minimum:0.5 maximum:1.8 default:1.0]];

        // --- Clock position slider ---
        PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:@"Clock Position"];
        [positionGroup setProperty:@"Slide left for higher up the screen, right for lower."
                            forKey:@"footerText"];
        [specifiers addObject:positionGroup];
        [specifiers addObject:[self sliderNamed:@"Clock Position" key:@"TimeYOffset"
                                         minimum:-100.0 maximum:100.0 default:0.0]];

        // --- Date position sliders ---
        PSSpecifier *dateGroup = [PSSpecifier groupSpecifierWithName:@"Date Position"];
        [dateGroup setProperty:@"Applies on your next lock/unlock rather than live."
                        forKey:@"footerText"];
        [specifiers addObject:dateGroup];
        [specifiers addObject:[self sliderNamed:@"Date Left / Right" key:@"DateXOffset"
                                         minimum:-100.0 maximum:100.0 default:0.0]];
        [specifiers addObject:[self sliderNamed:@"Date Up / Down" key:@"DateYOffset"
                                         minimum:-100.0 maximum:100.0 default:0.0]];

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
