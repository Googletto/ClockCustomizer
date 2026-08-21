// Minimal stand-in header for Preferences.framework's PSListController.
// See the note in PSSpecifier.h — same reasoning applies here.

#import <UIKit/UIKit.h>
#import "PSSpecifier.h"

@interface PSListController : UITableViewController {
    @protected
    NSMutableArray *_specifiers;
}

- (NSArray *)specifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifiers;
- (void)reloadSpecifier:(PSSpecifier *)specifier;

@end
