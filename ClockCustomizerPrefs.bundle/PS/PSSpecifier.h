// Minimal stand-in header for Preferences.framework's PSSpecifier.
// Apple doesn't ship headers for this private framework, so — like every
// other Settings-page tweak — we declare just enough of its interface
// ourselves to compile against it. The real class exists at runtime on
// every iOS device; we're only describing its shape to the compiler.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PSCellType) {
    PSGroupCell            = 0,
    PSLinkCell             = 1,
    PSLinkListCell         = 2,
    PSListItemCell         = 3,
    PSListItemsCell        = 4,
    PSStaticTextCell       = 5,
    PSTitleValueCell       = 6,
    PSSliderCell           = 7,
    PSSwitchCell           = 8,
    PSSegmentCell          = 9,
    PSEditTextCell         = 10,
    PSSecureEditTextCell   = 11,
    PSSelectionCell        = 12,
    PSSelectionListCell    = 13,
    PSSelectionCheckCell   = 14,
    PSTitleValueButtonCell = 15,
    PSButtonCell           = 16,
};

@interface PSSpecifier : NSObject

+ (instancetype)preferenceSpecifierNamed:(NSString *)name
                                   target:(id)target
                                      set:(SEL)set
                                      get:(SEL)get
                                   detail:(Class)detail
                                     cell:(PSCellType)cell
                                     edit:(Class)edit;

+ (instancetype)groupSpecifierWithName:(NSString *)name;

- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;

- (void)setValues:(NSArray *)values;
- (NSArray *)values;
- (void)setTitles:(NSArray *)titles;
- (NSArray *)titles;

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic) SEL getter;
@property (nonatomic) SEL setter;

@end
