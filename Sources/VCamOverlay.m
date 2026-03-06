/**
 * VCamOverlay.m
 * Renders watermark text onto CVPixelBuffers using CoreGraphics.
 * The watermark is semi-transparent and positioned at the top of the frame.
 */

#import "VCamOverlay.h"
#import "VCamConfig.h"
#import "VCamLogger.h"
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

@implementation VCamOverlay

+ (instancetype)sharedOverlay {
    static VCamOverlay *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamOverlay alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _watermarkText = @"TEST FEED — SIMULATED CAMERA";
    }
    return self;
}

- (void)applyWatermarkToPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return;
    if (![VCamConfig sharedConfig].watermarkEnabled) return;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);

    if (!baseAddress) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        return;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddress, width, height, 8, bytesPerRow, colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    if (ctx) {
        [self drawWatermarkInContext:ctx width:width height:height];
        CGContextRelease(ctx);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)drawWatermarkInContext:(CGContextRef)ctx width:(size_t)width height:(size_t)height {
    CGContextSaveGState(ctx);

    // CoreGraphics has Y-axis flipped for text
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    // Semi-transparent red banner at top
    CGFloat bannerHeight = height * 0.06;
    if (bannerHeight < 30) bannerHeight = 30;

    CGContextSetRGBFillColor(ctx, 0.8, 0.0, 0.0, 0.6);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, bannerHeight));

    // Draw main text
    CGFloat fontSize = bannerHeight * 0.55;
    if (fontSize < 12) fontSize = 12;

    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
        NSForegroundColorAttributeName: [UIColor whiteColor],
    };

    NSString *text = self.watermarkText;
    CGSize textSize = [text sizeWithAttributes:attrs];
    CGFloat x = (width - textSize.width) / 2.0;
    CGFloat y = (bannerHeight - textSize.height) / 2.0;

    UIGraphicsPushContext(ctx);
    [text drawAtPoint:CGPointMake(x, y) withAttributes:attrs];

    // Timestamp in smaller font at bottom-right of banner
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSString *timeStr = [df stringFromDate:[NSDate date]];

    NSDictionary *timeAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:fontSize * 0.6],
        NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.8],
    };
    CGSize timeSize = [timeStr sizeWithAttributes:timeAttrs];
    [timeStr drawAtPoint:CGPointMake(width - timeSize.width - 10,
                                     (bannerHeight - timeSize.height) / 2.0)
          withAttributes:timeAttrs];

    UIGraphicsPopContext();
    CGContextRestoreGState(ctx);
}

- (CVPixelBufferRef)pixelBufferWithWatermark:(CVPixelBufferRef)sourceBuffer {
    if (!sourceBuffer) return NULL;

    size_t width = CVPixelBufferGetWidth(sourceBuffer);
    size_t height = CVPixelBufferGetHeight(sourceBuffer);

    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };

    CVPixelBufferRef newBuffer = NULL;
    CVReturn ret = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
        kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &newBuffer);
    if (ret != kCVReturnSuccess) return NULL;

    // Copy source into new buffer
    CVPixelBufferLockBaseAddress(sourceBuffer, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(newBuffer, 0);

    void *srcBase = CVPixelBufferGetBaseAddress(sourceBuffer);
    void *dstBase = CVPixelBufferGetBaseAddress(newBuffer);
    size_t srcBPR = CVPixelBufferGetBytesPerRow(sourceBuffer);
    size_t dstBPR = CVPixelBufferGetBytesPerRow(newBuffer);

    for (size_t row = 0; row < height; row++) {
        memcpy((uint8_t *)dstBase + row * dstBPR,
               (uint8_t *)srcBase + row * srcBPR,
               MIN(srcBPR, dstBPR));
    }

    CVPixelBufferUnlockBaseAddress(sourceBuffer, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferUnlockBaseAddress(newBuffer, 0);

    // Apply watermark
    [self applyWatermarkToPixelBuffer:newBuffer];
    return newBuffer;
}

@end
