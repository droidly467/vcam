/**
 * VCamSessionHook.m
 * Implements camera feed replacement by hooking into AVCaptureSession
 * and related AVFoundation classes.
 *
 * Hook targets:
 * - AVCaptureVideoDataOutput's delegate method (captureOutput:didOutputSampleBuffer:fromConnection:)
 * - AVCaptureSession start/stop to manage media loader lifecycle
 * - AVCaptureDevice position to determine front/back camera
 * - AVCaptureStillImageOutput for photo capture hooks
 * - AVCapturePhotoOutput for modern photo capture
 */

#import "VCamSessionHook.h"
#import "VCamConfig.h"
#import "VCamMediaLoader.h"
#import "VCamOverlay.h"
#import "VCamLogger.h"
#import <objc/runtime.h>

static BOOL gHooksInstalled = NO;

// Store original IMPs for unhooking
static IMP gOriginalDelegateCallback = NULL;
static IMP gOriginalStartRunning = NULL;
static IMP gOriginalStopRunning = NULL;

@interface VCamSessionHook ()
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) NSUInteger replacedCount;
@property (nonatomic, assign) NSUInteger failedCount;
@property (nonatomic, strong) dispatch_queue_t hookQueue;
@end

@implementation VCamSessionHook

+ (instancetype)sharedHook {
    static VCamSessionHook *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamSessionHook alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _active = NO;
        _replacedCount = 0;
        _failedCount = 0;
        _hookQueue = dispatch_queue_create("com.vcam.hookqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isActive { return self.active; }
- (NSUInteger)framesReplaced { return self.replacedCount; }
- (NSUInteger)framesFailed { return self.failedCount; }

#pragma mark - Activation

- (void)activate {
    if (self.active) return;

    VCamConfig *cfg = [VCamConfig sharedConfig];
    if (!cfg.shouldInjectIntoCurrentProcess) {
        [VCamLogger log:@"SessionHook" message:@"Not allowed for this process, skipping"];
        return;
    }

    // Load configured media
    NSString *mediaPath = cfg.mediaFilePath;
    if (mediaPath) {
        BOOL loaded = [[VCamMediaLoader sharedLoader] loadMediaFromPath:mediaPath];
        if (!loaded) {
            [VCamLogger error:@"SessionHook" message:@"Failed to load media, will fall back to real camera"];
        }
    } else {
        [VCamLogger log:@"SessionHook" message:@"No media configured, will pass through real camera"];
    }

    self.active = YES;
    [VCamLogger log:@"SessionHook" message:@"Session hooks activated for %@",
        [[NSBundle mainBundle] bundleIdentifier]];
}

- (void)deactivate {
    self.active = NO;
    [[VCamMediaLoader sharedLoader] stopPlayback];
    [VCamLogger log:@"SessionHook" message:@"Session hooks deactivated"];
}

#pragma mark - Frame replacement

/**
 * Core frame replacement logic. Called from the hooked delegate method.
 * Returns the replacement sample buffer, or NULL to use the original.
 */
- (CMSampleBufferRef _Nullable)replacementBufferForOriginal:(CMSampleBufferRef)originalBuffer
                                              fromConnection:(AVCaptureConnection *)connection {
    if (!self.active) return NULL;

    VCamConfig *cfg = [VCamConfig sharedConfig];
    VCamMediaLoader *loader = [VCamMediaLoader sharedLoader];

    if (!loader.isLoaded) return NULL;

    // Check camera position filter
    if (connection.inputPorts.count > 0) {
        AVCaptureInputPort *port = connection.inputPorts.firstObject;
        AVCaptureInput *input = port.input;
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            AVCaptureDevicePosition pos = deviceInput.device.position;

            BOOL shouldReplace = NO;
            switch (cfg.simulatedPosition) {
                case VCamCameraPositionFront:
                    shouldReplace = (pos == AVCaptureDevicePositionFront);
                    break;
                case VCamCameraPositionBack:
                    shouldReplace = (pos == AVCaptureDevicePositionBack);
                    break;
                case VCamCameraPositionBoth:
                    shouldReplace = YES;
                    break;
            }

            if (!shouldReplace) return NULL;
        }
    }

    // Start playback if not already running
    if (!loader.isPlaying) {
        [loader startPlayback];
    }

    // Get format description from original buffer for compatibility
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(originalBuffer);

    @try {
        CMSampleBufferRef replacement = [loader currentSampleBufferWithFormatDescription:formatDesc];
        if (replacement) {
            // Apply watermark if enabled
            if (cfg.watermarkEnabled) {
                CVImageBufferRef imgBuf = CMSampleBufferGetImageBuffer(replacement);
                if (imgBuf) {
                    [[VCamOverlay sharedOverlay] applyWatermarkToPixelBuffer:imgBuf];
                }
            }

            self.replacedCount++;
            if (self.replacedCount % 300 == 0) {
                [VCamLogger debug:@"SessionHook" message:@"Frames replaced: %lu",
                    (unsigned long)self.replacedCount];
            }
            return replacement;
        }
    } @catch (NSException *e) {
        self.failedCount++;
        [VCamLogger error:@"SessionHook" message:@"Frame replacement exception: %@", e.reason];
    }

    self.failedCount++;
    return NULL; // Fallback to original
}

/**
 * Handle photo capture replacement (for AVCapturePhotoOutput).
 * Returns replacement photo data, or nil to use original.
 */
- (NSData *_Nullable)replacementPhotoData {
    if (!self.active) return nil;

    VCamMediaLoader *loader = [VCamMediaLoader sharedLoader];
    if (!loader.isLoaded) return nil;

    CVPixelBufferRef pixelBuffer = [loader currentPixelBuffer];
    if (!pixelBuffer) return nil;

    // Apply watermark if needed
    VCamConfig *cfg = [VCamConfig sharedConfig];
    if (cfg.watermarkEnabled) {
        CVPixelBufferRef watermarked = [[VCamOverlay sharedOverlay] pixelBufferWithWatermark:pixelBuffer];
        if (watermarked) {
            NSData *data = [self jpegDataFromPixelBuffer:watermarked];
            CVPixelBufferRelease(watermarked);
            return data;
        }
    }

    return [self jpegDataFromPixelBuffer:pixelBuffer];
}

- (NSData *)jpegDataFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CIContext *ciCtx = [CIContext context];
    CGImageRef cgImage = [ciCtx createCGImage:ciImage fromRect:ciImage.extent];
    if (!cgImage) return nil;

    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return UIImageJPEGRepresentation(image, 0.9);
}

@end
