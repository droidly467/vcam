/**
 * VCamConfig.h
 * Configuration manager for VCam tweak.
 * Reads preferences from the rootless prefs path and provides
 * a clean interface for all modules to query settings.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kVCamPrefsChangedNotification;
extern NSString *const kVCamPrefsDomain;
extern NSString *const kVCamPrefsPath;

typedef NS_ENUM(NSInteger, VCamCameraPosition) {
    VCamCameraPositionFront = 0,
    VCamCameraPositionBack  = 1,
    VCamCameraPositionBoth  = 2,
};

typedef NS_ENUM(NSInteger, VCamMediaType) {
    VCamMediaTypeNone  = 0,
    VCamMediaTypeImage = 1,
    VCamMediaTypeVideo = 2,
};

@interface VCamConfig : NSObject

@property (nonatomic, readonly) BOOL tweakEnabled;
@property (nonatomic, readonly) BOOL globalEnabled;
@property (nonatomic, readonly) BOOL watermarkEnabled;
@property (nonatomic, readonly) BOOL loopVideo;
@property (nonatomic, readonly) BOOL debugLogEnabled;
@property (nonatomic, readonly) VCamCameraPosition simulatedPosition;
@property (nonatomic, readonly) VCamMediaType mediaType;
@property (nonatomic, readonly, nullable) NSString *mediaFilePath;
@property (nonatomic, readonly) NSArray<NSString *> *allowedBundleIDs;
@property (nonatomic, readonly) BOOL bypassDetectionEnabled;

+ (instancetype)sharedConfig;

- (void)reloadConfig;
- (void)resetToDefaults;

- (BOOL)isAppAllowed:(NSString *)bundleID;
- (BOOL)shouldInjectIntoCurrentProcess;

@end

NS_ASSUME_NONNULL_END
