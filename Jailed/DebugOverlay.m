#import "DebugOverlay.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "SideloadIdentity.h"
#import "../UI/GSAccountConnection.h"
#import "../UI/GSNativeAccount.h"

static NSString *GSRuntimeEntitlementString(NSString *name) {
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return @"-";

    CFTypeRef raw = SecTaskCopyValueForEntitlement(
        task,
        (__bridge CFStringRef)name,
        NULL
    );

    NSString *result = @"-";

    if (raw) {
        id value = CFBridgingRelease(raw);

        if ([value isKindOfClass:NSString.class]) {
            result = value.length ? value : @"-";
        } else if ([value isKindOfClass:NSArray.class]) {
            result = [(NSArray *)value componentsJoinedByString:@","];
            if (!result.length) result = @"-";
        } else {
            result = [value description] ?: @"-";
        }
    }

    CFRelease(task);
    return result;
}

static NSDictionary *GSRuntimeEntitlementSnapshot(void) {
    return @{
        @"applicationIdentifier":
            GSRuntimeEntitlementString(@"application-identifier"),
        @"teamIdentifier":
            GSRuntimeEntitlementString(@"com.apple.developer.team-identifier"),
        @"keychainAccessGroups":
            GSRuntimeEntitlementString(@"keychain-access-groups"),
        @"getTaskAllow":
            GSRuntimeEntitlementString(@"get-task-allow"),
        @"apsEnvironment":
            GSRuntimeEntitlementString(@"aps-environment")
    };
}
static UILabel *GSLabel;
static NSString *GSStatus = @"loading";

static void GSUpdate(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!GSLabel) return;

        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"?";
        NSString *exec = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"?";
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
        NSDictionary *connection = GSAccountConnectionSnapshot();
        NSString *connectionState = connection[@"state"] ?: @"?";
        NSString *nativeState = GSNativeAccountDebugState() ?: @"?";

        NSDictionary *identity = GSSideloadIdentitySnapshot();
        NSDictionary *runtimeEntitlements = GSRuntimeEntitlementSnapshot();
        NSString *runtimeIdentityState = [NSString stringWithFormat:@"appId=%@ team=%@ keychain=%@ taskAllow=%@ aps=%@", runtimeEntitlements[@"applicationIdentifier"], runtimeEntitlements[@"teamIdentifier"], runtimeEntitlements[@"keychainAccessGroups"], runtimeEntitlements[@"getTaskAllow"], runtimeEntitlements[@"apsEnvironment"]];
                NSDictionary *webAuth = GSWebAuthDiagnosticsSnapshot();
        NSString *webAuthState = [NSString stringWithFormat:@"created=%@ started=%@ completed=%@ success=%@ cancel=%@ create=%@ start=%@ completion=%@ error=%@/%@", webAuth[@"created"], webAuth[@"started"], webAuth[@"completed"], webAuth[@"succeeded"], webAuth[@"cancelled"], webAuth[@"createCount"], webAuth[@"startCount"], webAuth[@"completionCount"], webAuth[@"errorDomain"], webAuth[@"errorCode"]];
NSDictionary *oauth = identity[@"oauth"];
        NSString *oauthState = [NSString stringWithFormat:@"callback=%@ count=%@ channel=%@",
            oauth[@"callbackReceived"], oauth[@"callbackCount"], oauth[@"callbackChannel"]];

        NSString *text = [NSString stringWithFormat:
            @"GUNSHOT DEBUG\\n"
             "bundle = %@\\n"
             "exec = %@\\n"
             "version = %@\\n"
             "identityHook = cfg=%@ svc=%@\\n"
             "identityUsed = cfg=%@ svc=%@\\n"
             "connection = %@\n"
             "native = %@"
             "oauth = %@\nwebAuth = %@\nruntimeIdentity = %@"
             "status = %@",
            bundle,
            exec,
            version,
            identity[@"configurationHook"],
            identity[@"bundleServiceHook"],
            identity[@"configurationUsed"],
            identity[@"bundleServiceUsed"],
            connectionState,
            nativeState,
            oauthState,
            webAuthState,
            runtimeIdentityState,
            GSStatus ?: @"-"];

        GSLabel.text = text;
    });
}

void GSDebugSetStatus(NSString *status) {
    GSStatus = [status copy];
    GSUpdate();
}

void GSDebugInstallOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL installed = NO;
        if (installed) {
            GSUpdate();
            return;
        }

        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;

            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow && candidate.windowLevel == UIWindowLevelNormal) {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }

        if (!window) {
            // Deprecated since iOS 13: intentionally removed.
        }

        if (!window) return;

        GSLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        GSLabel.numberOfLines = 0;
        GSLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        GSLabel.textColor = UIColor.whiteColor;
        GSLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
        GSLabel.layer.cornerRadius = 8;
        GSLabel.layer.masksToBounds = YES;
        GSLabel.userInteractionEnabled = NO;
        GSLabel.textAlignment = NSTextAlignmentLeft;
        GSLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [window addSubview:GSLabel];

        UILayoutGuide *safe = window.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [GSLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
            [GSLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
            [GSLabel.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor multiplier:0.94],
        ]];

        installed = YES;
        GSUpdate();
    });
}


