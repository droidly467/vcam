/**
 * VCamLogger.m
 * Logging implementation.
 * Uses os_log for syslog and writes to a log file under
 * /var/jb/var/mobile/Library/VCamMedia/vcam.log
 */

#import "VCamLogger.h"
#import <os/log.h>

static NSString *const kVCamLogFile = @"/var/jb/var/mobile/Library/VCamMedia/vcam.log";
static const NSUInteger kMaxLogFileSize = 2 * 1024 * 1024; // 2MB rotation

static os_log_t vcamOSLog(void) {
    static os_log_t log = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.vcam.qatool", "VCam");
    });
    return log;
}

@implementation VCamLogger

+ (void)log:(NSString *)module message:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *full = [NSString stringWithFormat:@"[VCam][%@] %@", module, msg];
    os_log(vcamOSLog(), "%{public}@", full);
    [self writeToFile:full];
}

+ (void)error:(NSString *)module message:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *full = [NSString stringWithFormat:@"[VCam][ERROR][%@] %@", module, msg];
    os_log_error(vcamOSLog(), "%{public}@", full);
    [self writeToFile:full];
}

+ (void)debug:(NSString *)module message:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    // Debug only logs if debug flag is on — but we check at call site
    // to avoid overhead. This always writes if called.
    NSString *full = [NSString stringWithFormat:@"[VCam][DEBUG][%@] %@", module, msg];
    os_log_debug(vcamOSLog(), "%{public}@", full);
    [self writeToFile:full];
}

#pragma mark - File logging

+ (void)writeToFile:(NSString *)message {
    static dispatch_queue_t logQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("com.vcam.logqueue", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(logQueue, ^{
        @try {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dir = [kVCamLogFile stringByDeletingLastPathComponent];
            if (![fm fileExistsAtPath:dir]) {
                [fm createDirectoryAtPath:dir
                    withIntermediateDirectories:YES
                    attributes:nil
                    error:nil];
            }

            // Rotate if too large
            NSDictionary *attrs = [fm attributesOfItemAtPath:kVCamLogFile error:nil];
            if (attrs && [attrs fileSize] > kMaxLogFileSize) {
                NSString *oldLog = [kVCamLogFile stringByAppendingString:@".old"];
                [fm removeItemAtPath:oldLog error:nil];
                [fm moveItemAtPath:kVCamLogFile toPath:oldLog error:nil];
            }

            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            NSString *timestamp = [df stringFromDate:[NSDate date]];

            NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

            if (![fm fileExistsAtPath:kVCamLogFile]) {
                [fm createFileAtPath:kVCamLogFile contents:data attributes:nil];
            } else {
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kVCamLogFile];
                [fh seekToEndOfFile];
                [fh writeData:data];
                [fh closeFile];
            }
        } @catch (NSException *e) {
            // Silently fail — cannot log a logging failure
        }
    });
}

+ (void)flushLogFile {
    // Force sync write
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:kVCamLogFile]) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kVCamLogFile];
        [fh synchronizeFile];
        [fh closeFile];
    }
}

+ (NSString *)logFilePath {
    return kVCamLogFile;
}

@end
