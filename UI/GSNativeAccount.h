#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void GSInstallNativeAccount(void);
// Metadata only. Call on main; no token is returned to UI or persisted.
FOUNDATION_EXPORT NSDictionary *GSNativeAccountSummary(void);
// Jailed debug metadata only; no OAuth credentials.
FOUNDATION_EXPORT NSString *GSNativeAccountDebugState(void);
// Worker-thread C ABI: caller owns the malloc-allocated result. NULL on failure.
FOUNDATION_EXPORT char *GSNativeBearer(const char *identifier);
// Main thread; compare an opaque native accountID (e.g. GIPGaiaAccountID).
// This is NOT the SSO userID string returned by the summary's identifier field.
FOUNDATION_EXPORT BOOL GSNativeAccountMatches(id accountID);
// Main thread; compare a nonempty SSO userID string against the signed-in identity.
FOUNDATION_EXPORT BOOL GSNativeIdentityMatches(NSString *identifier);
