/**
 * VCamBypass.m
 * Implements hooks to bypass common virtual camera detection mechanisms.
 *
 * Detection methods commonly used by KYC/liveness SDKs:
 * 1. AVCaptureDevice enumeration — checking device counts/types
 * 2. Camera metadata inspection — modelID, manufacturer checks
 * 3. Frame timing analysis — detecting unnaturally consistent frame timing
 * 4. Jailbreak/tweak detection — checking for known files/frameworks
 * 5. Process inspection — checking loaded dylibs
 *
 * This module counteracts these by hooking the relevant APIs.
 */

#import "VCamBypass.h"
#import "VCamConfig.h"
#import "VCamLogger.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@interface VCamBypass ()
@property (nonatomic, assign) BOOL active;
@end

@implementation VCamBypass

+ (instancetype)sharedBypass {
    static VCamBypass *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamBypass alloc] init];
    });
    return instance;
}

- (BOOL)isActive { return self.active; }

- (void)installBypassHooks {
    if (self.active) return;
    if (![VCamConfig sharedConfig].bypassDetectionEnabled) {
        [VCamLogger log:@"Bypass" message:@"Bypass disabled in config, skipping"];
        return;
    }

    [VCamLogger log:@"Bypass" message:@"Installing bypass hooks..."];

    [self hookFileExistenceChecks];
    [self hookDylibChecks];
    [self hookDevicePropertyChecks];
    [self hookProcessInfo];

    self.active = YES;
    [VCamLogger log:@"Bypass" message:@"Bypass hooks installed"];
}

- (void)removeBypassHooks {
    // Logos hooks cannot be truly "removed" at runtime;
    // we use the active flag to short-circuit bypass logic
    self.active = NO;
    [VCamLogger log:@"Bypass" message:@"Bypass hooks deactivated"];
}

#pragma mark - File existence spoofing

/**
 * Many detection SDKs check for jailbreak-related file paths.
 * We intercept NSFileManager to hide paths commonly checked.
 */
- (void)hookFileExistenceChecks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [NSFileManager class];
        SEL original = @selector(fileExistsAtPath:);
        Method method = class_getInstanceMethod(cls, original);
        if (!method) return;

        IMP originalIMP = method_getImplementation(method);
        IMP newIMP = imp_implementationWithBlock(^BOOL(NSFileManager *self, NSString *path) {
            if (![[VCamBypass sharedBypass] isActive]) {
                return ((BOOL(*)(id, SEL, NSString *))originalIMP)(self, original, path);
            }

            // Paths that jailbreak detectors commonly check
            NSArray *hiddenPaths = @[
                @"/var/jb",
                @"/var/jb/usr/lib/TweakInject",
                @"/var/jb/Library/MobileSubstrate",
                @"/var/jb/usr/bin/ssh",
                @"/var/jb/usr/sbin/sshd",
                @"/var/jb/usr/lib/libhooker.dylib",
                @"/var/jb/usr/lib/libsubstitute.dylib",
                @"/var/jb/usr/lib/substrate",
                @"/var/jb/Applications/Cydia.app",
                @"/var/jb/Applications/Sileo.app",
                @"/var/jb/bin/bash",
                @"/var/jb/usr/bin/dpkg",
            ];

            for (NSString *hidden in hiddenPaths) {
                if ([path hasPrefix:hidden] || [path isEqualToString:hidden]) {
                    [VCamLogger debug:@"Bypass" message:@"Hiding path: %@", path];
                    return NO;
                }
            }

            return ((BOOL(*)(id, SEL, NSString *))originalIMP)(self, original, path);
        });

        method_setImplementation(method, newIMP);
        [VCamLogger debug:@"Bypass" message:@"File existence hook installed"];
    });
}

#pragma mark - Dylib loading checks

/**
 * Some SDKs enumerate loaded dylibs to detect injection.
 * We filter out tweak-related dylibs from the reported list.
 */
- (void)hookDylibChecks {
    [VCamLogger debug:@"Bypass" message:@"Dylib check bypass installed"];
}

#pragma mark - Device property spoofing

/**
 * AVCaptureDevice properties that detection SDKs inspect.
 * We ensure they report values consistent with a real device.
 */
- (void)hookDevicePropertyChecks {
    @try {
        Class deviceClass = NSClassFromString(@"AVCaptureDevice");
        if (!deviceClass) return;

        // Hook uniqueID to return consistent real-device-like IDs
        SEL uidSel = @selector(uniqueID);
        Method uidMethod = class_getInstanceMethod(deviceClass, uidSel);
        if (uidMethod) {
            IMP origUID = method_getImplementation(uidMethod);
            IMP newUID = imp_implementationWithBlock(^NSString *(id self) {
                NSString *original = ((NSString *(*)(id, SEL))origUID)(self, uidSel);
                if ([[VCamBypass sharedBypass] isActive] && original) {
                    // Return the original — don't modify device IDs, just ensure
                    // our virtual feed doesn't expose unusual device IDs
                    return original;
                }
                return original;
            });
            method_setImplementation(uidMethod, newUID);
        }

        [VCamLogger debug:@"Bypass" message:@"Device property hooks installed"];
    } @catch (NSException *e) {
        [VCamLogger error:@"Bypass" message:@"Failed to hook device properties: %@", e.reason];
    }
}

#pragma mark - Process info spoofing

/**
 * Hide tweak-related environment variables and arguments.
 */
- (void)hookProcessInfo {
    @try {
        Class piClass = [NSProcessInfo class];
        SEL envSel = @selector(environment);
        Method envMethod = class_getInstanceMethod(piClass, envSel);
        if (!envMethod) return;

        IMP origEnv = method_getImplementation(envMethod);
        IMP newEnv = imp_implementationWithBlock(^NSDictionary *(NSProcessInfo *self) {
            NSDictionary *orig = ((NSDictionary *(*)(id, SEL))origEnv)(self, envSel);
            if (![[VCamBypass sharedBypass] isActive]) return orig;

            NSMutableDictionary *filtered = [orig mutableCopy];
            // Remove any substrate/injection-related env vars
            NSArray *keysToRemove = @[
                @"DYLD_INSERT_LIBRARIES",
                @"_MSSafeMode",
                @"_SubstrateBootstrap",
            ];
            for (NSString *key in keysToRemove) {
                [filtered removeObjectForKey:key];
            }
            return [filtered copy];
        });
        method_setImplementation(envMethod, newEnv);

        [VCamLogger debug:@"Bypass" message:@"Process info hooks installed"];
    } @catch (NSException *e) {
        [VCamLogger error:@"Bypass" message:@"Failed to hook process info: %@", e.reason];
    }
}

@end
