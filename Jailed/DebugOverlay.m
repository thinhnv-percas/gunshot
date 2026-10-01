#import "DebugOverlay.h"
#import <UIKit/UIKit.h>
#import "SideloadIdentity.h"

static UILabel *GSLabel;
static NSString *GSStatus = @"loading";

static void GSUpdate(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!GSLabel) return;

        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"?";
        NSString *exec = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"?";
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";

        NSDictionary *identity = GSSideloadIdentitySnapshot();

        NSString *text = [NSString stringWithFormat:
            @"GUNSHOT DEBUG\\n"
             "bundle = %@\\n"
             "exec = %@\\n"
             "version = %@\\n"
             "identityHook = cfg=%@ svc=%@\\n"
             "identityUsed = cfg=%@ svc=%@\\n"
             "status = %@",
            bundle,
            exec,
            version,
            identity[@"configurationHook"],
            identity[@"bundleServiceHook"],
            identity[@"configurationUsed"],
            identity[@"bundleServiceUsed"],
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
            window = UIApplication.sharedApplication.keyWindow;
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
