/**
 * VCamMediaLoader.h
 * Responsible for loading test media (image/video) from local files
 * and converting them to CMSampleBufferRef frames suitable for
 * injection into the camera pipeline.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VCamMediaLoaderDelegate <NSObject>
@optional
- (void)mediaLoaderDidProduceFrame:(CMSampleBufferRef)sampleBuffer;
- (void)mediaLoaderDidEncounterError:(NSError *)error;
- (void)mediaLoaderDidFinishPlayback;
@end

@interface VCamMediaLoader : NSObject

@property (nonatomic, weak, nullable) id<VCamMediaLoaderDelegate> delegate;
@property (nonatomic, readonly) BOOL isLoaded;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) CGSize frameSize;

+ (instancetype)sharedLoader;

/**
 * Load media from the configured path.
 * Returns YES if media was loaded successfully.
 */
- (BOOL)loadMediaFromPath:(NSString *)path;

/**
 * Start producing frames. For images, produces a single static frame.
 * For video, starts decoding frames at native framerate.
 */
- (void)startPlayback;
- (void)stopPlayback;
- (void)pausePlayback;
- (void)resumePlayback;

/**
 * Get current frame as CVPixelBufferRef.
 * Caller does NOT own the returned buffer (do not release).
 */
- (nullable CVPixelBufferRef)currentPixelBuffer;

/**
 * Get current frame as CMSampleBufferRef matching the given format.
 * Caller OWNS the returned buffer (must CFRelease).
 */
- (nullable CMSampleBufferRef)currentSampleBufferWithFormatDescription:(CMFormatDescriptionRef _Nullable)formatDesc;

- (void)unloadMedia;

@end

NS_ASSUME_NONNULL_END
