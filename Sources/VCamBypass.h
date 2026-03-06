/**
 * VCamBypass.h
 * Bypass module for evading virtual camera detection.
 * Hooks into common detection methods used by KYC/liveness/anti-fraud SDKs
 * to prevent them from detecting that a simulated feed is being used.
 *
 * Targets common detection patterns:
 * - Device model/name checks
 * - Camera device enumeration validation
 * - AVCaptureSession property inspection
 * - IOKit registry queries for camera hardware
 * - Jailbreak detection (related to camera spoofing checks)
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCamBypass : NSObject

+ (instancetype)sharedBypass;

/**
 * Install all bypass hooks. Called once during tweak initialization
 * if bypass detection is enabled in config.
 */
- (void)installBypassHooks;

/**
 * Remove bypass hooks and restore original behavior.
 */
- (void)removeBypassHooks;

@property (nonatomic, readonly) BOOL isActive;

@end

NS_ASSUME_NONNULL_END
