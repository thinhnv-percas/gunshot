#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../UI/GSPanel.h"
#import "../UI/GSAccountMenu.h"
#import "../UI/GSNativeRouting.h"
#import "../UI/GSPhotosIntegration.h"
#import "../UI/GSAccountConnection.h"
#import "../UI/GSUploadMonitor.h"
#import "SideloadKeychain.h"
#import "SideloadIdentity.h"
#import "DebugOverlay.h"

static id (*GSOriginalActivityInit)(id, SEL, NSArray *, NSArray *);

static id GSActivityInit(id object, SEL selector, NSArray *items, NSArray *activities) {
    NSMutableArray *all = activities ? [activities mutableCopy] : [NSMutableArray array];
    GSUploadActivity *upload = [GSUploadActivity new];
    if ([upload canPerformWithActivityItems:items]) [all addObject:upload];
    return GSOriginalActivityInit(object, selector, items, all);
}

__attribute__((constructor))
static void GSLoadJailed(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            GSDebugInstallOverlay();
            GSDebugSetStatus(@"dylib constructor executed");
        });

        GSInstallSideloadIdentity();
        // OAuth callback diagnostics are scheduled by the identity installer.

        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *identity = GSSideloadIdentitySnapshot();

            if ([identity[@"configurationHook"] boolValue] ||
                [identity[@"bundleServiceHook"] boolValue]) {
                GSDebugSetStatus(@"SSO identity hook installed");
            } else {
                GSDebugSetStatus(@"WARNING: no SSO identity hook");
            }
        });

        GSInstallSideloadKeychain();

        dispatch_async(dispatch_get_main_queue(), ^{
            GSDebugSetStatus(@"identity + keychain initialized");

            NSString *executable =
                [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];

            if (![executable isEqualToString:@"GooglePhotos"]) {
                GSDebugSetStatus([NSString stringWithFormat:
                    @"WARNING: executable=%@", executable ?: @"nil"]);
                return;
            }

            GSStartAccountConnection();

            [NSNotificationCenter.defaultCenter
                addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil
                queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
                    GSResumeAccountConnection();

                    NSDictionary *identity = GSSideloadIdentitySnapshot();
                    if ([identity[@"configurationUsed"] boolValue] ||
                        [identity[@"bundleServiceUsed"] boolValue]) {
                        GSDebugSetStatus(@"SSO identity hook USED");
                    } else {
                        GSDebugSetStatus(@"Google SSO hook not used yet");
                    }
                }];

            GSInstallAccountMenu();
            GSStartBackupIntegration();

            Method activity =
                class_getInstanceMethod(
                    UIActivityViewController.class,
                    @selector(initWithActivityItems:applicationActivities:));

            if (activity) {
                GSOriginalActivityInit =
                    (void *)method_setImplementation(
                        activity, (IMP)GSActivityInit);
            }

            GSDebugSetStatus(@"GooglePhotos host initialized");
        });
    }
}
