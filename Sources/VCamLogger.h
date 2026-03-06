/**
 * VCamLogger.h
 * Centralized logging for VCam tweak.
 * Logs to both syslog (Console/oslog) and optionally to a file
 * for easy QA debugging.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCamLogger : NSObject

+ (void)log:(NSString *)module message:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2, 3);
+ (void)error:(NSString *)module message:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2, 3);
+ (void)debug:(NSString *)module message:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2, 3);

+ (void)flushLogFile;
+ (nullable NSString *)logFilePath;

@end

NS_ASSUME_NONNULL_END
