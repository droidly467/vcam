/**
 * VCamSessionHook.h
 * Core camera session hooking module.
 * Intercepts AVCaptureSession and AVCaptureVideoDataOutput
 * to replace real camera frames with simulated media.
 *
 * Hook strategy:
 * 1. Hook AVCaptureVideoDataOutput delegate callbacks
 * 2. Replace CMSampleBuffer with our simulated buffer
 * 3. Maintain proper timing and format compatibility
 * 4. Fall back to real camera on any error
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCamSessionHook : NSObject

+ (instancetype)sharedHook;

/**
 * Initialize the hook system. Must be called during tweak load.
 * Sets up all AVFoundation hooks.
 */
- (void)activate;

/**
 * Deactivate hooks. Restores original camera behavior.
 */
- (void)deactivate;

@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly) NSUInteger framesReplaced;
@property (nonatomic, readonly) NSUInteger framesFailed;

@end

NS_ASSUME_NONNULL_END
