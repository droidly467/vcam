/**
 * VCamAppListController.m
 * App allowlist selector. Displays installed apps and lets the user
 * toggle which ones should receive simulated camera input.
 */

#import "VCamAppListController.h"
#import <notify.h>
#import <objc/runtime.h>

static NSString *const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist";
static NSString *const kPrefsNotification = @"com.vcam.qatool/prefsChanged";

@interface VCamAppListController ()
@property (nonatomic, strong) NSMutableArray *installedApps;
@property (nonatomic, strong) NSMutableSet *selectedBundleIDs;
@end

@implementation VCamAppListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"App Allowlist";
    [self loadInstalledApps];
    [self loadSelectedApps];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // Header
        PSSpecifier *header = [PSSpecifier groupSpecifierWithName:@"Select Target Apps"];
        [header setProperty:@"Apps not in the list will not receive simulated camera feed. If no apps are selected, ALL apps will be affected."
                     forKey:@"footerText"];
        [specs addObject:header];

        // Common test apps (hardcoded for convenience)
        NSArray *commonApps = @[
            @{@"name": @"Safari", @"bundle": @"com.apple.mobilesafari"},
            @{@"name": @"Camera", @"bundle": @"com.apple.camera"},
            @{@"name": @"FaceTime", @"bundle": @"com.apple.facetime"},
            @{@"name": @"WhatsApp", @"bundle": @"net.whatsapp.WhatsApp"},
            @{@"name": @"Telegram", @"bundle": @"ph.telegra.Telegraph"},
            @{@"name": @"Instagram", @"bundle": @"com.burbn.instagram"},
            @{@"name": @"Snapchat", @"bundle": @"com.toyopagroup.picaboo"},
            @{@"name": @"TikTok", @"bundle": @"com.zhiliaoapp.musically"},
            @{@"name": @"Zoom", @"bundle": @"us.zoom.videomeetings"},
            @{@"name": @"Teams", @"bundle": @"com.microsoft.skype.teams"},
            @{@"name": @"Facebook", @"bundle": @"com.facebook.Facebook"},
            @{@"name": @"Messenger", @"bundle": @"com.facebook.Messenger"},
            @{@"name": @"WeChat", @"bundle": @"com.tencent.xin"},
            @{@"name": @"LINE", @"bundle": @"jp.naver.line"},
            @{@"name": @"Zalo", @"bundle": @"com.vng.zalo"},
            @{@"name": @"Viber", @"bundle": @"com.viber"},
            @{@"name": @"Signal", @"bundle": @"org.whispersystems.signal"},
            @{@"name": @"Skype", @"bundle": @"com.skype.skype"},
        ];

        PSSpecifier *commonHeader = [PSSpecifier groupSpecifierWithName:@"Common Apps"];
        [specs addObject:commonHeader];

        for (NSDictionary *app in commonApps) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
                                                              target:self
                                                                 set:@selector(toggleApp:specifier:)
                                                                 get:@selector(getAppState:)
                                                              detail:nil
                                                                cell:PSSwitchCell
                                                                edit:nil];
            [spec setProperty:app[@"bundle"] forKey:@"bundleID"];
            [spec setProperty:@NO forKey:@"default"];
            [specs addObject:spec];
        }

        // Custom bundle ID input
        PSSpecifier *customHeader = [PSSpecifier groupSpecifierWithName:@"Custom App"];
        [customHeader setProperty:@"Enter a custom bundle identifier to add to the allowlist."
                           forKey:@"footerText"];
        [specs addObject:customHeader];

        PSSpecifier *customInput = [PSSpecifier preferenceSpecifierNamed:@"Add Bundle ID"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSButtonCell
                                                                   edit:nil];
        [customInput setProperty:@"addCustomBundleID" forKey:@"action"];
        customInput->action = @selector(addCustomBundleID);
        [specs addObject:customInput];

        // Selected apps summary
        PSSpecifier *selectedHeader = [PSSpecifier groupSpecifierWithName:@"Currently Selected"];
        [specs addObject:selectedHeader];

        _specifiers = specs;
    }
    return _specifiers;
}

#pragma mark - App state management

- (id)getAppState:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    return @([self.selectedBundleIDs containsObject:bundleID]);
}

- (void)toggleApp:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    if (!bundleID) return;

    if ([value boolValue]) {
        [self.selectedBundleIDs addObject:bundleID];
    } else {
        [self.selectedBundleIDs removeObject:bundleID];
    }

    [self saveSelectedApps];
}

#pragma mark - Persistence

- (void)loadSelectedApps {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    NSArray *saved = prefs[@"allowedBundleIDs"];
    self.selectedBundleIDs = saved ? [NSMutableSet setWithArray:saved] : [NSMutableSet set];
}

- (void)saveSelectedApps {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!prefs) prefs = [NSMutableDictionary dictionary];

    prefs[@"allowedBundleIDs"] = [self.selectedBundleIDs allObjects];
    [prefs writeToFile:kPrefsPath atomically:YES];

    notify_post(kPrefsNotification.UTF8String);
}

#pragma mark - App enumeration

- (void)loadInstalledApps {
    self.installedApps = [NSMutableArray array];

    // Use LSApplicationWorkspace to enumerate installed apps
    Class lsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!lsClass) return;

    id workspace = [lsClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return;

    NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
    for (id proxy in apps) {
        NSString *bundleID = [proxy performSelector:@selector(applicationIdentifier)];
        NSString *name = [proxy performSelector:@selector(localizedName)];
        if (bundleID && name) {
            [self.installedApps addObject:@{@"name": name, @"bundle": bundleID}];
        }
    }

    [self.installedApps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
}

#pragma mark - Custom Bundle ID

- (void)addCustomBundleID {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Add Custom Bundle ID"
        message:@"Enter the bundle identifier of the app"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"com.example.app";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Add"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *bundleID = alert.textFields.firstObject.text;
        if (bundleID.length > 0) {
            [self.selectedBundleIDs addObject:bundleID];
            [self saveSelectedApps];
            [self reloadSpecifiers];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
