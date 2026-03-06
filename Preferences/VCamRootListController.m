/**
 * VCamRootListController.m
 * Main preferences controller for VCam settings in iOS Settings app.
 * Handles all UI interactions and preferences persistence.
 */

#import "VCamRootListController.h"
#import <notify.h>

static NSString *const kPrefsDomain = @"com.vcam.qatool";
static NSString *const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist";
static NSString *const kPrefsNotification = @"com.vcam.qatool/prefsChanged";

@implementation VCamRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"VCam";
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return nil;

    id value = prefs[key];
    if (!value) {
        value = [specifier propertyForKey:@"default"];
    }
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!prefs) prefs = [NSMutableDictionary dictionary];

    prefs[key] = value;
    [prefs writeToFile:kPrefsPath atomically:YES];

    notify_post(kPrefsNotification.UTF8String);
}

#pragma mark - Actions

- (void)resetSettings {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Settings"
        message:@"This will reset all VCam settings to defaults. Are you sure?"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        NSDictionary *defaults = @{
            @"tweakEnabled"          : @YES,
            @"globalEnabled"         : @YES,
            @"watermarkEnabled"      : @YES,
            @"loopVideo"             : @YES,
            @"debugLogEnabled"       : @YES,
            @"simulatedPosition"     : @2,
            @"mediaType"             : @0,
            @"mediaFilePath"         : @"",
            @"allowedBundleIDs"      : @[],
            @"bypassDetectionEnabled": @NO,
        };

        [defaults writeToFile:kPrefsPath atomically:YES];
        notify_post(kPrefsNotification.UTF8String);

        [self reloadSpecifiers];

        UIAlertController *done = [UIAlertController
            alertControllerWithTitle:@"Done"
            message:@"Settings have been reset to defaults."
            preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
        [self presentViewController:done animated:YES completion:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
