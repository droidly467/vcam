/**
 * VCamConfig.m
 * Manages all tweak preferences. Reads from rootless prefs directory.
 * Listens for preference changes via Darwin notifications.
 */

#import "VCamConfig.h"
#import "VCamLogger.h"
#import <notify.h>

NSString *const kVCamPrefsChangedNotification = @"com.vcam.qatool/prefsChanged";
NSString *const kVCamPrefsDomain = @"com.vcam.qatool";

// Rootless prefs path
NSString *const kVCamPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist";

// Rootless media storage path
static NSString *const kVCamMediaBasePath = @"/var/jb/var/mobile/Library/VCamMedia";

@interface VCamConfig ()
@property (nonatomic, strong) NSDictionary *prefs;
@end

@implementation VCamConfig

+ (instancetype)sharedConfig {
    static VCamConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reloadConfig];
        [self registerNotificationObserver];
    }
    return self;
}

- (void)registerNotificationObserver {
    int token;
    notify_register_dispatch(
        kVCamPrefsChangedNotification.UTF8String,
        &token,
        dispatch_get_main_queue(),
        ^(int t) {
            [self reloadConfig];
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"VCamConfigDidReload" object:nil];
        }
    );
}

#pragma mark - Loading

- (void)reloadConfig {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kVCamPrefsPath];
    if (!dict) {
        dict = [self defaultPrefs];
        [VCamLogger log:@"Config" message:@"No prefs file found, using defaults"];
    }
    self.prefs = dict;
    [VCamLogger log:@"Config" message:@"Config reloaded: %@", dict];
}

- (NSDictionary *)defaultPrefs {
    return @{
        @"tweakEnabled"          : @YES,
        @"globalEnabled"         : @YES,
        @"watermarkEnabled"      : @YES,
        @"loopVideo"             : @YES,
        @"debugLogEnabled"       : @YES,
        @"simulatedPosition"     : @(VCamCameraPositionBoth),
        @"mediaType"             : @(VCamMediaTypeNone),
        @"mediaFilePath"         : @"",
        @"allowedBundleIDs"      : @[],
        @"bypassDetectionEnabled": @NO,
    };
}

- (void)resetToDefaults {
    NSDictionary *defaults = [self defaultPrefs];
    [defaults writeToFile:kVCamPrefsPath atomically:YES];
    [self reloadConfig];
    notify_post(kVCamPrefsChangedNotification.UTF8String);
    [VCamLogger log:@"Config" message:@"Config reset to defaults"];
}

#pragma mark - Accessors

- (BOOL)tweakEnabled {
    return [self boolForKey:@"tweakEnabled" defaultValue:YES];
}

- (BOOL)globalEnabled {
    return [self boolForKey:@"globalEnabled" defaultValue:YES];
}

- (BOOL)watermarkEnabled {
    return [self boolForKey:@"watermarkEnabled" defaultValue:YES];
}

- (BOOL)loopVideo {
    return [self boolForKey:@"loopVideo" defaultValue:YES];
}

- (BOOL)debugLogEnabled {
    return [self boolForKey:@"debugLogEnabled" defaultValue:YES];
}

- (BOOL)bypassDetectionEnabled {
    return [self boolForKey:@"bypassDetectionEnabled" defaultValue:NO];
}

- (VCamCameraPosition)simulatedPosition {
    NSNumber *val = self.prefs[@"simulatedPosition"];
    return val ? (VCamCameraPosition)val.integerValue : VCamCameraPositionBoth;
}

- (VCamMediaType)mediaType {
    NSNumber *val = self.prefs[@"mediaType"];
    return val ? (VCamMediaType)val.integerValue : VCamMediaTypeNone;
}

- (NSString *)mediaFilePath {
    NSString *path = self.prefs[@"mediaFilePath"];
    if (!path || path.length == 0) return nil;

    // If relative path, resolve against media base
    if (![path hasPrefix:@"/"]) {
        path = [kVCamMediaBasePath stringByAppendingPathComponent:path];
    }
    return path;
}

- (NSArray<NSString *> *)allowedBundleIDs {
    NSArray *arr = self.prefs[@"allowedBundleIDs"];
    return [arr isKindOfClass:[NSArray class]] ? arr : @[];
}

#pragma mark - Query

- (BOOL)isAppAllowed:(NSString *)bundleID {
    if (!bundleID) return NO;
    NSArray *allowed = self.allowedBundleIDs;
    if (allowed.count == 0) return YES; // empty = allow all
    return [allowed containsObject:bundleID];
}

- (BOOL)shouldInjectIntoCurrentProcess {
    if (!self.tweakEnabled || !self.globalEnabled) {
        return NO;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return NO;

    // Never inject into system apps we shouldn't touch
    NSArray *blacklist = @[
        @"com.apple.springboard",
        @"com.apple.Preferences",
    ];
    if ([blacklist containsObject:bundleID]) return NO;

    return [self isAppAllowed:bundleID];
}

#pragma mark - Helpers

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def {
    NSNumber *val = self.prefs[key];
    return val ? val.boolValue : def;
}

@end
