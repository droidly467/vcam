/**
 * VCamOverlay.h
 * Draws watermark/overlay text onto pixel buffers.
 * Shows "TEST FEED" or "SIMULATED CAMERA" text to clearly
 * indicate this is not a real camera feed.
 */

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCamOverlay : NSObject

+ (instancetype)sharedOverlay;

/**
 * Apply watermark overlay to a pixel buffer in-place.
 * Draws translucent "TEST FEED" text with timestamp.
 */
- (void)applyWatermarkToPixelBuffer:(CVPixelBufferRef)pixelBuffer;

/**
 * Create a new pixel buffer with watermark applied.
 * Caller owns the returned buffer.
 */
- (nullable CVPixelBufferRef)pixelBufferWithWatermark:(CVPixelBufferRef)sourceBuffer;

/**
 * Custom watermark text. Defaults to "TEST FEED — SIMULATED CAMERA".
 */
@property (nonatomic, copy) NSString *watermarkText;

@end

NS_ASSUME_NONNULL_END
