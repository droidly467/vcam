/**
 * Tweak.x
 * VCam — Virtual Camera QA Tool
 *
 * Main hook file. Uses Logos syntax to hook into AVFoundation classes
 * and replace camera feed with simulated media for testing.
 *
 * Architecture:
 * - Config: VCamConfig (preferences management)
 * - Media: VCamMediaLoader (image/video loading & frame production)
 * - Hooks: This file + VCamSessionHook (AVFoundation interception)
 * - Overlay: VCamOverlay (watermark rendering)
 * - Bypass: VCamBypass (detection evasion)
 * - Logging: VCamLogger (centralized logging)
 */

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "Sources/VCamConfig.h"
#import "Sources/VCamMediaLoader.h"
#import "Sources/VCamSessionHook.h"
#import "Sources/VCamOverlay.h"
#import "Sources/VCamBypass.h"
#import "Sources/VCamLogger.h"

// ============================================================================
// MARK: - AVCaptureVideoDataOutput Delegate Hook
// ============================================================================
// This is the primary hook. Most camera apps receive frames through
// AVCaptureVideoDataOutputSampleBufferDelegate. We intercept the delegate
// callback and replace the sample buffer with our simulated one.

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if ([VCamConfig sharedConfig].shouldInjectIntoCurrentProcess &&
        [VCamConfig sharedConfig].tweakEnabled) {

        [VCamLogger log:@"Hook" message:@"Hooking setSampleBufferDelegate for %@",
            NSStringFromClass([delegate class])];

        // Wrap the delegate to intercept frame callbacks
        if (delegate && [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self vcam_hookDelegateClass:[delegate class]];
        }
    }

    %orig(delegate, queue);
}

%new
- (void)vcam_hookDelegateClass:(Class)delegateClass {
    static NSMutableSet *hookedClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hookedClasses = [NSMutableSet set];
    });

    NSString *className = NSStringFromClass(delegateClass);
    if ([hookedClasses containsObject:className]) return;
    [hookedClasses addObject:className];

    SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    Method method = class_getInstanceMethod(delegateClass, sel);
    if (!method) return;

    IMP originalIMP = method_getImplementation(method);

    IMP newIMP = imp_implementationWithBlock(^(id self, AVCaptureOutput *output,
                                               CMSampleBufferRef sampleBuffer,
                                               AVCaptureConnection *connection) {
        @autoreleasepool {
            VCamSessionHook *hook = [VCamSessionHook sharedHook];
            CMSampleBufferRef replacement = [hook replacementBufferForOriginal:sampleBuffer
                                                               fromConnection:connection];
            if (replacement) {
                ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))
                    originalIMP)(self, sel, output, replacement, connection);
                CFRelease(replacement);
            } else {
                // Fallback: pass through original buffer
                ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))
                    originalIMP)(self, sel, output, sampleBuffer, connection);
            }
        }
    });

    method_setImplementation(method, newIMP);
    [VCamLogger log:@"Hook" message:@"Hooked delegate class: %@", className];
}

%end


// ============================================================================
// MARK: - AVCaptureSession Lifecycle Hooks
// ============================================================================
// Track session start/stop to manage media loader lifecycle.

%hook AVCaptureSession

- (void)startRunning {
    [VCamLogger log:@"Hook" message:@"AVCaptureSession startRunning"];

    VCamConfig *cfg = [VCamConfig sharedConfig];
    if (cfg.shouldInjectIntoCurrentProcess && cfg.tweakEnabled) {
        [[VCamSessionHook sharedHook] activate];
        [[VCamMediaLoader sharedLoader] startPlayback];
        [VCamLogger log:@"Hook" message:@"VCam activated for session"];
    }

    %orig;
}

- (void)stopRunning {
    [VCamLogger log:@"Hook" message:@"AVCaptureSession stopRunning"];

    [[VCamMediaLoader sharedLoader] stopPlayback];
    %orig;
}

%end


// ============================================================================
// MARK: - AVCapturePhotoOutput Hook (iOS 10+)
// ============================================================================
// Hook photo capture to replace still photos with simulated content.

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if ([VCamConfig sharedConfig].shouldInjectIntoCurrentProcess &&
        [VCamConfig sharedConfig].tweakEnabled) {

        [VCamLogger log:@"Hook" message:@"Photo capture intercepted"];

        if (delegate) {
            [self vcam_hookPhotoDelegateClass:[delegate class]];
        }
    }
    %orig(settings, delegate);
}

%new
- (void)vcam_hookPhotoDelegateClass:(Class)delegateClass {
    static NSMutableSet *hookedPhotoClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hookedPhotoClasses = [NSMutableSet set];
    });

    NSString *className = NSStringFromClass(delegateClass);
    if ([hookedPhotoClasses containsObject:className]) return;
    [hookedPhotoClasses addObject:className];

    // Hook the photo output delegate to provide replacement photo
    SEL photoSel = @selector(captureOutput:didFinishProcessingPhoto:error:);
    Method photoMethod = class_getInstanceMethod(delegateClass, photoSel);
    if (!photoMethod) return;

    IMP origPhoto = method_getImplementation(photoMethod);
    IMP newPhoto = imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *output,
                                                 AVCapturePhoto *photo, NSError *error) {
        // Cannot easily replace AVCapturePhoto, so we pass through
        // The video feed replacement is the primary mechanism
        ((void(*)(id, SEL, AVCapturePhotoOutput *, AVCapturePhoto *, NSError *))
            origPhoto)(self, photoSel, output, photo, error);
    });

    method_setImplementation(photoMethod, newPhoto);
    [VCamLogger log:@"Hook" message:@"Photo delegate hooked: %@", className];
}

%end


// ============================================================================
// MARK: - AVCaptureDevice Hook
// ============================================================================
// Hook device discovery to ensure consistent behavior when virtual feed is active.

%hook AVCaptureDevice

+ (NSArray *)devicesWithMediaType:(NSString *)mediaType {
    NSArray *devices = %orig;
    if ([VCamConfig sharedConfig].debugLogEnabled) {
        [VCamLogger debug:@"Hook" message:@"devicesWithMediaType:%@ returned %lu devices",
            mediaType, (unsigned long)devices.count];
    }
    return devices;
}

- (BOOL)isTorchAvailable {
    // When simulating, torch is not available
    VCamConfig *cfg = [VCamConfig sharedConfig];
    if (cfg.shouldInjectIntoCurrentProcess && cfg.tweakEnabled &&
        [VCamSessionHook sharedHook].isActive) {
        return NO;
    }
    return %orig;
}

%end


// ============================================================================
// MARK: - AVCaptureDeviceDiscoverySession Hook (iOS 10+)
// ============================================================================

%hook AVCaptureDeviceDiscoverySession

- (NSArray<AVCaptureDevice *> *)devices {
    NSArray *devices = %orig;
    if ([VCamConfig sharedConfig].debugLogEnabled) {
        NSMutableArray *names = [NSMutableArray array];
        for (AVCaptureDevice *d in devices) {
            [names addObject:[NSString stringWithFormat:@"%@ (pos:%ld)",
                d.localizedName, (long)d.position]];
        }
        [VCamLogger debug:@"Hook" message:@"Discovery session devices: %@",
            [names componentsJoinedByString:@", "]];
    }
    return devices;
}

%end


// ============================================================================
// MARK: - UIImagePickerController Hook
// ============================================================================
// Some apps use UIImagePickerController for camera. Hook it too.

%hook UIImagePickerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    VCamConfig *cfg = [VCamConfig sharedConfig];
    if (cfg.shouldInjectIntoCurrentProcess && cfg.tweakEnabled) {
        if (self.sourceType == UIImagePickerControllerSourceTypeCamera) {
            [VCamLogger log:@"Hook" message:@"UIImagePickerController camera view appeared"];
            // The underlying AVCaptureSession hooks will handle the feed replacement
        }
    }
}

%end


// ============================================================================
// MARK: - Tweak Constructor
// ============================================================================

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];

        [VCamLogger log:@"Init" message:@"VCam loading in process: %@ (pid: %d)",
            bundleID, getpid()];

        VCamConfig *cfg = [VCamConfig sharedConfig];

        // Early exit if tweak is disabled
        if (!cfg.tweakEnabled || !cfg.globalEnabled) {
            [VCamLogger log:@"Init" message:@"Tweak disabled globally, not loading"];
            return;
        }

        // Check if this app is in the allowlist
        if (!cfg.shouldInjectIntoCurrentProcess) {
            [VCamLogger log:@"Init" message:@"App %@ not in allowlist, skipping", bundleID];
            return;
        }

        [VCamLogger log:@"Init" message:@"VCam active for: %@", bundleID];

        // Install bypass hooks if enabled
        if (cfg.bypassDetectionEnabled) {
            [[VCamBypass sharedBypass] installBypassHooks];
        }

        // Pre-load media if configured
        NSString *mediaPath = cfg.mediaFilePath;
        if (mediaPath && mediaPath.length > 0) {
            BOOL loaded = [[VCamMediaLoader sharedLoader] loadMediaFromPath:mediaPath];
            [VCamLogger log:@"Init" message:@"Media pre-load %@: %@",
                loaded ? @"success" : @"FAILED", mediaPath];
        } else {
            [VCamLogger log:@"Init" message:@"No media path configured"];
        }

        [VCamLogger log:@"Init" message:@"VCam initialization complete"];
    }
}
