#import "../Shared/GSPhotosCompatibility.h"
#import "GSNativeAccount.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

@interface GSAccountSource : NSObject
@property(atomic,weak) id manager;
@end
@implementation GSAccountSource
@end
static GSAccountSource *GSSource;
#if GS_JAILED
static NSString *GSDebugNativeAccountState =
    @"manager=unset viewing=unset identity=unset auth=unset user=unset";

static void GSDebugNativeAccountRecord(NSString *state) {
    GSDebugNativeAccountState = [state copy];
}

NSString *GSNativeAccountDebugState(void) {
    return GSDebugNativeAccountState ?: @"unknown";
}
#else
NSString *GSNativeAccountDebugState(void) {
    return @"unavailable";
}
#endif
static id (*GSViewingAccountOriginal)(id,SEL);
static id GSViewingAccount(id object,SEL selector){GSSource.manager=object;return GSViewingAccountOriginal(object,selector);}
static BOOL GSMethod(id object,NSString *name,const char *encoding){
 Method method=class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name));
 return method&&strcmp(method_getTypeEncoding(method),encoding)==0;
}
static id GSGet(id object,NSString *name){
 if(!GSMethod(object,name,"@16@0:8"))return nil;
 return ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(name));
}
static id GSIdentity(id account){
 if(![account isKindOfClass:NSClassFromString(@"PHSAccount")])return nil;
 Ivar ivar=class_getInstanceVariable(NSClassFromString(@"PHSAccount"),"_ssoIdentity");
 if(!ivar||strcmp(ivar_getTypeEncoding(ivar),"@\"<SSOIdentity>\""))return nil;
 id identity=object_getIvar(account,ivar);
 if(!GSMethod(identity,@"hasValidAuth","B16@0:8")||!((BOOL(*)(id,SEL))objc_msgSend)(identity,NSSelectorFromString(@"hasValidAuth")))return nil;
 return identity;
}
NSDictionary *GSNativeAccountSummary(void){
 if(!NSThread.isMainThread){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=off-main viewing=- identity=- auth=- user=-");
#endif
  return nil;
 }

 id manager=GSSource.manager;
 if(!manager){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=nil viewing=- identity=- auth=- user=-");
#endif
  return nil;
 }

 id account=GSGet(manager,@"viewingAccount");
 if(!account){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=ok viewing=nil identity=- auth=- user=-");
#endif
  return nil;
 }

 Class accountClass=NSClassFromString(@"PHSAccount");
 if(![account isKindOfClass:accountClass]){
#if GS_JAILED
  GSDebugNativeAccountRecord([NSString stringWithFormat:
    @"manager=ok viewing=ok class=%@ identity=- auth=- user=-",
    NSStringFromClass([account class]) ?: @"unknown"]);
#endif
  return nil;
 }

 Ivar ivar=class_getInstanceVariable(accountClass,"_ssoIdentity");
 if(!ivar||strcmp(ivar_getTypeEncoding(ivar),"@\"<SSOIdentity>\"")){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=ok viewing=ok identity=missing auth=- user=-");
#endif
  return nil;
 }

 id identity=object_getIvar(account,ivar);
 if(!identity){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=ok viewing=ok identity=nil auth=- user=-");
#endif
  return nil;
 }

 if(!GSMethod(identity,@"hasValidAuth","B16@0:8")){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=ok viewing=ok identity=ok auth=method-missing user=-");
#endif
  return nil;
 }

 BOOL validAuth=((BOOL(*)(id,SEL))objc_msgSend)(
    identity,NSSelectorFromString(@"hasValidAuth"));

 if(!validAuth){
#if GS_JAILED
  GSDebugNativeAccountRecord(@"manager=ok viewing=ok identity=ok auth=invalid user=-");
#endif
  return nil;
 }

 NSString *email=GSGet(identity,@"userEmail");
 NSString *identifier=GSGet(identity,@"userID");
 BOOL validEmail=[email isKindOfClass:NSString.class]&&email.length>0;
 BOOL validID=[identifier isKindOfClass:NSString.class]&&identifier.length>0;

#if GS_JAILED
 if(!validEmail||!validID){
  GSDebugNativeAccountRecord([NSString stringWithFormat:
    @"manager=ok viewing=ok identity=ok auth=valid user=email:%@ id:%@",
    validEmail?@"ok":@"missing",
    validID?@"ok":@"missing"]);
  return nil;
 }

 GSDebugNativeAccountRecord(
    @"manager=ok viewing=ok identity=ok auth=valid user=valid");
#endif

 if(!validEmail||!validID)return nil;
 return @{@"email":email,@"identifier":identifier};
}
BOOL GSNativeAccountMatches(id accountID){
 if(!NSThread.isMainThread||!accountID)return NO;
 return [GSGet(GSGet(GSSource.manager,@"viewingAccount"),@"accountID")isEqual:accountID];
}
BOOL GSNativeIdentityMatches(NSString *identifier){
 if(!NSThread.isMainThread||![identifier isKindOfClass:NSString.class]||!identifier.length)return NO;
 return [GSNativeAccountSummary()[@"identifier"]isEqualToString:identifier];
}
void GSInstallNativeAccount(void){
 if(GSSource||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"]||!GSPhotosHostSupported())return;
 Class cls=NSClassFromString(@"PHSAccountManagerImpl");Method method=class_getInstanceMethod(cls,NSSelectorFromString(@"viewingAccount"));
 if(!method||strcmp(method_getTypeEncoding(method),"@16@0:8"))return;
 GSSource=[GSAccountSource new];GSViewingAccountOriginal=(void *)method_setImplementation(method,(IMP)GSViewingAccount);
}
char *GSNativeBearer(const char *identifier){
 @autoreleasepool {
 if(NSThread.isMainThread||!identifier)return NULL; // Never block the UI / SSO callback queue.
 NSString *expected=[NSString stringWithUTF8String:identifier];if(!expected.length)return NULL;
 dispatch_semaphore_t ready=dispatch_semaphore_create(0);
 NSObject *lock=[NSObject new];__block NSString *token=nil;__block BOOL finished=NO;
 void (^finish)(NSString *)=^(NSString *value){@synchronized(lock){if(finished)return;finished=YES;token=[value copy];}dispatch_semaphore_signal(ready);};
 dispatch_async(dispatch_get_main_queue(),^{
 @try {
 if(![GSNativeAccountSummary()[@"identifier"]isEqual:expected]){finish(nil);return;}
 id manager=GSSource.manager;id account=GSGet(manager,@"viewingAccount");id accountID=GSGet(account,@"accountID");
 id service=GSGet(manager,@"photosSSOService");
 NSString *factory=@"fetcherAuthorizerForAccountID:scopes:";id subject=accountID;
 if(!GSMethod(service,factory,"@32@0:8@16@24")){
  service=GSGet(manager,@"ssoService");factory=@"authorizationForIdentity:scopes:";subject=GSIdentity(account);
 }
 if(!subject||!GSMethod(service,factory,"@32@0:8@16@24")){finish(nil);return;}
 id authorizer=((id(*)(id,SEL,id,id))objc_msgSend)(service,NSSelectorFromString(factory),subject,@[@"https://www.googleapis.com/auth/photos.native"]);
 if(!GSMethod(authorizer,@"authorizeRequest:completionHandler:","v32@0:8@16@?24")){finish(nil);return;}
 // This request is only authorized, never sent. SSO owns refresh and its Keychain.
 NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://photos.googleapis.com/data/upload/uploadmedia/interactive"]];
 ((void(*)(id,SEL,id,id))objc_msgSend)(authorizer,NSSelectorFromString(@"authorizeRequest:completionHandler:"),request,^(NSError *error){
  dispatch_async(dispatch_get_main_queue(),^{
   (void)authorizer; // Keep the native authorizer alive until its callback completes.
   if(error||![GSNativeAccountSummary()[@"identifier"]isEqual:expected]){finish(nil);return;}
   NSString *header=[request valueForHTTPHeaderField:@"Authorization"];
   if(![header hasPrefix:@"Bearer "]){finish(nil);return;}
   NSString *value=[header substringFromIndex:7];
   if(!value.length||value.length>32768||[value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound){finish(nil);return;}
   finish(value);
  });
 });
 }@catch(NSException *exception){finish(nil);} // No native error/exception description crosses the bridge.
 });
 if(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))!=0){@synchronized(lock){finished=YES;token=nil;}return NULL;}
 @synchronized(lock){return token?strdup(token.UTF8String):NULL;}
 }
}
