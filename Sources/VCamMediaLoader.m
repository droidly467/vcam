/**
 * VCamMediaLoader.m
 * Handles loading images and videos from local filesystem,
 * converting them to pixel buffers, and producing CMSampleBuffers
 * for camera feed injection.
 */

#import "VCamMediaLoader.h"
#import "VCamConfig.h"
#import "VCamLogger.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>

@interface VCamMediaLoader ()

@property (nonatomic, strong, nullable) AVAssetReader *assetReader;
@property (nonatomic, strong, nullable) AVAssetReaderTrackOutput *videoOutput;
@property (nonatomic, strong, nullable) AVAsset *videoAsset;
@property (nonatomic, strong, nullable) UIImage *staticImage;
@property (nonatomic, assign) CVPixelBufferRef currentBuffer;
@property (nonatomic, strong, nullable) dispatch_source_t frameTimer;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) CGSize loadedFrameSize;
@property (nonatomic, strong, nullable) NSString *currentMediaPath;
@property (nonatomic, assign) VCamMediaType currentMediaType;

@end

@implementation VCamMediaLoader

+ (instancetype)sharedLoader {
    static VCamMediaLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamMediaLoader alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _loaded = NO;
        _playing = NO;
        _currentBuffer = NULL;
    }
    return self;
}

- (void)dealloc {
    [self unloadMedia];
}

#pragma mark - Properties

- (BOOL)isLoaded { return self.loaded; }
- (BOOL)isPlaying { return self.playing; }
- (CGSize)frameSize { return self.loadedFrameSize; }

#pragma mark - Loading

- (BOOL)loadMediaFromPath:(NSString *)path {
    [self unloadMedia];

    if (!path || path.length == 0) {
        [VCamLogger error:@"MediaLoader" message:@"Empty media path"];
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [VCamLogger error:@"MediaLoader" message:@"File not found: %@", path];
        return NO;
    }

    NSString *ext = path.pathExtension.lowercaseString;
    NSSet *imageExts = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"bmp", @"tiff"]];
    NSSet *videoExts = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi"]];

    if ([imageExts containsObject:ext]) {
        return [self loadImage:path];
    } else if ([videoExts containsObject:ext]) {
        return [self loadVideo:path];
    } else {
        [VCamLogger error:@"MediaLoader" message:@"Unsupported format: %@", ext];
        return NO;
    }
}

- (BOOL)loadImage:(NSString *)path {
    @try {
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (!img) {
            [VCamLogger error:@"MediaLoader" message:@"Failed to decode image: %@", path];
            return NO;
        }

        self.staticImage = img;
        self.currentMediaType = VCamMediaTypeImage;
        self.currentMediaPath = path;
        self.loadedFrameSize = img.size;

        CVPixelBufferRef pixelBuffer = [self pixelBufferFromImage:img];
        if (!pixelBuffer) {
            [VCamLogger error:@"MediaLoader" message:@"Failed to create pixel buffer from image"];
            return NO;
        }

        if (self.currentBuffer) {
            CVPixelBufferRelease(self.currentBuffer);
        }
        self.currentBuffer = pixelBuffer;
        self.loaded = YES;

        [VCamLogger log:@"MediaLoader" message:@"Loaded image: %@ (%dx%d)",
            path, (int)img.size.width, (int)img.size.height];
        return YES;
    } @catch (NSException *e) {
        [VCamLogger error:@"MediaLoader" message:@"Exception loading image: %@", e.reason];
        return NO;
    }
}

- (BOOL)loadVideo:(NSString *)path {
    @try {
        NSURL *url = [NSURL fileURLWithPath:path];
        self.videoAsset = [AVAsset assetWithURL:url];

        NSArray *videoTracks = [self.videoAsset tracksWithMediaType:AVMediaTypeVideo];
        if (videoTracks.count == 0) {
            [VCamLogger error:@"MediaLoader" message:@"No video track in: %@", path];
            return NO;
        }

        AVAssetTrack *track = videoTracks.firstObject;
        self.loadedFrameSize = track.naturalSize;
        self.currentMediaType = VCamMediaTypeVideo;
        self.currentMediaPath = path;
        self.loaded = YES;

        [VCamLogger log:@"MediaLoader" message:@"Loaded video: %@ (%dx%d, %.1f fps)",
            path, (int)track.naturalSize.width, (int)track.naturalSize.height,
            track.nominalFrameRate];
        return YES;
    } @catch (NSException *e) {
        [VCamLogger error:@"MediaLoader" message:@"Exception loading video: %@", e.reason];
        return NO;
    }
}

#pragma mark - Playback

- (void)startPlayback {
    if (!self.loaded) return;

    if (self.currentMediaType == VCamMediaTypeImage) {
        self.playing = YES;
        [VCamLogger debug:@"MediaLoader" message:@"Image playback started (static frame)"];
        return;
    }

    if (self.currentMediaType == VCamMediaTypeVideo) {
        [self startVideoDecoding];
    }
}

- (void)stopPlayback {
    self.playing = NO;
    if (self.frameTimer) {
        dispatch_source_cancel(self.frameTimer);
        self.frameTimer = nil;
    }
    if (self.assetReader) {
        [self.assetReader cancelReading];
        self.assetReader = nil;
    }
    self.videoOutput = nil;
    [VCamLogger debug:@"MediaLoader" message:@"Playback stopped"];
}

- (void)pausePlayback {
    self.playing = NO;
}

- (void)resumePlayback {
    if (self.loaded) {
        self.playing = YES;
    }
}

- (void)startVideoDecoding {
    NSError *error = nil;
    self.assetReader = [[AVAssetReader alloc] initWithAsset:self.videoAsset error:&error];
    if (error) {
        [VCamLogger error:@"MediaLoader" message:@"Failed to create asset reader: %@", error];
        return;
    }

    NSArray *videoTracks = [self.videoAsset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) return;

    AVAssetTrack *track = videoTracks.firstObject;
    NSDictionary *outputSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferWidthKey: @((int)track.naturalSize.width),
        (NSString *)kCVPixelBufferHeightKey: @((int)track.naturalSize.height),
    };

    self.videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:outputSettings];
    self.videoOutput.alwaysCopiesSampleData = NO;

    if ([self.assetReader canAddOutput:self.videoOutput]) {
        [self.assetReader addOutput:self.videoOutput];
    }

    if (![self.assetReader startReading]) {
        [VCamLogger error:@"MediaLoader" message:@"Asset reader failed to start: %@",
            self.assetReader.error];
        return;
    }

    self.playing = YES;
    float fps = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30.0f;
    NSTimeInterval interval = 1.0 / fps;

    self.frameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    dispatch_source_set_timer(self.frameTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        (uint64_t)(interval * NSEC_PER_SEC),
        (uint64_t)(0.001 * NSEC_PER_SEC));

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.frameTimer, ^{
        [weakSelf decodeNextFrame];
    });
    dispatch_resume(self.frameTimer);

    [VCamLogger log:@"MediaLoader" message:@"Video playback started at %.1f fps", fps];
}

- (void)decodeNextFrame {
    if (!self.playing || !self.assetReader) return;

    if (self.assetReader.status == AVAssetReaderStatusCompleted) {
        VCamConfig *cfg = [VCamConfig sharedConfig];
        if (cfg.loopVideo) {
            [VCamLogger debug:@"MediaLoader" message:@"Video loop — restarting"];
            [self stopPlayback];
            [self startVideoDecoding];
            return;
        } else {
            [self stopPlayback];
            if ([self.delegate respondsToSelector:@selector(mediaLoaderDidFinishPlayback)]) {
                [self.delegate mediaLoaderDidFinishPlayback];
            }
            return;
        }
    }

    if (self.assetReader.status != AVAssetReaderStatusReading) return;

    CMSampleBufferRef sampleBuffer = [self.videoOutput copyNextSampleBuffer];
    if (!sampleBuffer) return;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        CVPixelBufferRetain(imageBuffer);
        @synchronized(self) {
            if (self.currentBuffer) {
                CVPixelBufferRelease(self.currentBuffer);
            }
            self.currentBuffer = imageBuffer;
        }
    }

    if ([self.delegate respondsToSelector:@selector(mediaLoaderDidProduceFrame:)]) {
        [self.delegate mediaLoaderDidProduceFrame:sampleBuffer];
    }

    CFRelease(sampleBuffer);
}

#pragma mark - Frame access

- (CVPixelBufferRef)currentPixelBuffer {
    @synchronized(self) {
        return self.currentBuffer;
    }
}

- (CMSampleBufferRef)currentSampleBufferWithFormatDescription:(CMFormatDescriptionRef)formatDesc {
    @synchronized(self) {
        if (!self.currentBuffer) return NULL;
        return [self createSampleBufferFromPixelBuffer:self.currentBuffer formatDescription:formatDesc];
    }
}

- (CMSampleBufferRef)createSampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                     formatDescription:(CMFormatDescriptionRef)inputFormatDesc {
    if (!pixelBuffer) return NULL;

    CMSampleBufferRef sampleBuffer = NULL;
    CMFormatDescriptionRef formatDesc = inputFormatDesc;

    if (!formatDesc) {
        OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault, pixelBuffer, &formatDesc);
        if (status != noErr) {
            [VCamLogger error:@"MediaLoader" message:@"Failed to create format description: %d", (int)status];
            return NULL;
        }
    } else {
        CFRetain(formatDesc);
    }

    CMSampleTimingInfo timing;
    timing.duration = CMTimeMake(1, 30);
    timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
    timing.decodeTimeStamp = kCMTimeInvalid;

    OSStatus status = CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        YES,
        NULL, NULL,
        formatDesc,
        &timing,
        &sampleBuffer);

    CFRelease(formatDesc);

    if (status != noErr) {
        [VCamLogger error:@"MediaLoader" message:@"Failed to create sample buffer: %d", (int)status];
        return NULL;
    }

    return sampleBuffer;
}

#pragma mark - Pixel buffer from image

- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return NULL;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn cvret = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &pixelBuffer);

    if (cvret != kCVReturnSuccess) {
        [VCamLogger error:@"MediaLoader" message:@"CVPixelBufferCreate failed: %d", cvret];
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddr, width, height, 8, bytesPerRow, colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(ctx);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

#pragma mark - Cleanup

- (void)unloadMedia {
    [self stopPlayback];
    @synchronized(self) {
        if (self.currentBuffer) {
            CVPixelBufferRelease(self.currentBuffer);
            self.currentBuffer = NULL;
        }
    }
    self.staticImage = nil;
    self.videoAsset = nil;
    self.currentMediaPath = nil;
    self.loaded = NO;
    [VCamLogger debug:@"MediaLoader" message:@"Media unloaded"];
}

@end
