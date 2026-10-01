#import "SideloadIdentity.h"
#import <UIKit/UIKit.h>
#import "../Shared/GSPhotosCompatibility.h"
#import <objc/message.h>
#include <stdatomic.h>
#include <stdlib.h>

static NSString *GSInstalledBundleID;
static id (*GSOriginalApplicationIdentifier)(id,SEL);
static id (*GSOriginalSSOBundleID)(id,SEL);
static atomic_bool GSApplicationIdentityUsed,GSBundleIdentityUsed;
static atomic_bool GSOAuthCallbackReceived;
static atomic_uint GSOAuthCallbackCount;
static NSString *GSOAuthCallbackChannel = @"none";

static void GSOAuthRecordCallback(NSString *channel) {
    atomic_store(&GSOAuthCallbackReceived, true);
    atomic_fetch_add(&GSOAuthCallbackCount, 1);
    GSOAuthCallbackChannel = [channel copy] ?: @"unknown";
}

static NSString *GSOAuthCallbackState(void) {
    unsigned int count = atomic_load(&GSOAuthCallbackCount);
    return [NSString stringWithFormat:@"callback=%@ count=%u channel=%@",
        atomic_load(&GSOAuthCallbackReceived) ? @"1" : @"0",
        count,
        GSOAuthCallbackChannel ?: @"none"];
}

static BOOL (*GSOriginalApplicationOpenURL)(id,SEL,NSURL *,NSDictionary *);
static BOOL GSApplicationOpenURL(id object,SEL selector,NSURL *url,NSDictionary *options) {
    GSOAuthRecordCallback(@"application.openURL");
    return GSOriginalApplicationOpenURL(object,selector,url,options);
}

static BOOL (*GSOriginalApplicationContinueUserActivity)(id,SEL,NSUserActivity *,void (^)(NSArray *));
static BOOL GSApplicationContinueUserActivity(id object,SEL selector,NSUserActivity *activity,void (^restoration)(NSArray *)) {
    GSOAuthRecordCallback(@"application.continueUserActivity");
    return GSOriginalApplicationContinueUserActivity(object,selector,activity,restoration);
}

static void (*GSOriginalSceneOpenURLContexts)(id,SEL,UIScene *,NSSet *);
static void GSSceneOpenURLContexts(id object,SEL selector,UIScene *scene,NSSet *contexts) {
    GSOAuthRecordCallback(@"scene.openURLContexts");
    GSOriginalSceneOpenURLContexts(object,selector,scene,contexts);
}

static BOOL GSHookInstanceMethodIfOwned(Class cls,SEL selector,IMP replacement,IMP *original,const char *abi) {
    if(!cls)return NO;
    Method method=class_getInstanceMethod(cls,selector);
    if(!method||strcmp(method_getTypeEncoding(method),abi)!=0)return NO;
    Class parent=class_getSuperclass(cls);
    if(parent&&class_getInstanceMethod(parent,selector)==method)return NO;
    if(*original)return YES;
    *original=(IMP)method_getImplementation(method);
    method_setImplementation(method,replacement);
    return YES;
}

static void GSOAuthInstallDelegateHooks(void) {
    UIApplication *application=UIApplication.sharedApplication;
    id delegate=application.delegate;
    if(delegate){
        Class cls=object_getClass(delegate);
        GSHookInstanceMethodIfOwned(
            cls,
            @selector(application:openURL:options:),
            (IMP)GSApplicationOpenURL,
            (IMP *)&GSOriginalApplicationOpenURL,
            "B32@0:8@16@24");

        GSHookInstanceMethodIfOwned(
            cls,
            @selector(application:continueUserActivity:restorationHandler:),
            (IMP)GSApplicationContinueUserActivity,
            (IMP *)&GSOriginalApplicationContinueUserActivity,
            "B48@0:8@16@24@?32");
    }

    for(UIScene *scene in application.connectedScenes){
        id sceneDelegate=scene.delegate;
        if(!sceneDelegate)continue;
        Class cls=object_getClass(sceneDelegate);
        GSHookInstanceMethodIfOwned(
            cls,
            @selector(scene:openURLContexts:),
            (IMP)GSSceneOpenURLContexts,
            (IMP *)&GSOriginalSceneOpenURLContexts,
            "v32@0:8@16@24");
    }
}

static void GSOAuthScheduleDelegateHookRetry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSInteger attempts=0;
        if(attempts++>=40)return;
        GSOAuthInstallDelegateHooks();
        if(!GSOriginalApplicationOpenURL &&
           !GSOriginalApplicationContinueUserActivity &&
           !GSOriginalSceneOpenURLContexts){
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),
                dispatch_get_main_queue(),
                ^{ GSOAuthScheduleDelegateHookRetry(); });
        }
    });
}

NSDictionary *GSOAuthDiagnosticsSnapshot(void) {
    return @{
        @"callbackReceived":@(atomic_load(&GSOAuthCallbackReceived)),
        @"callbackCount":@(atomic_load(&GSOAuthCallbackCount)),
        @"callbackChannel":GSOAuthCallbackChannel ?: @"none"
    };
}


static id GSApplicationIdentifier(id object,SEL selector){
 id value=GSOriginalApplicationIdentifier(object,selector);
 if(![value isEqual:GSInstalledBundleID])return value;
 id client=((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"clientID"));
 // This client and its registered callback scheme are shared by both audited IPAs.
 if(![client isEqual:@"278930400967-s7eptfh2d81vvi86kptt63pfa0o5usjt.apps.googleusercontent.com"])return value;
 atomic_store(&GSApplicationIdentityUsed,YES);
 return @"com.google.photos";
}
static id GSSSOBundleID(id object,SEL selector){
 id value=GSOriginalSSOBundleID(object,selector);
 if(![value isEqual:GSInstalledBundleID])return value;
 atomic_store(&GSBundleIdentityUsed,YES);
 return @"com.google.photos";
}
void GSInstallSideloadIdentity(void){
 const char *liveContainer=getenv("LC_HOME_PATH");
 if((liveContainer&&*liveContainer)||!GSPhotosHostSupported())return;
 id identifier=NSBundle.mainBundle.bundleIdentifier;
 if(![identifier isKindOfClass:NSString.class]||![identifier length]||[identifier isEqual:@"com.google.photos"])return;
 @synchronized(NSBundle.class){
  if(!GSInstalledBundleID)GSInstalledBundleID=[identifier copy];
  Class configuration=NSClassFromString(@"SSOConfiguration");
  if(!GSOriginalApplicationIdentifier&&
     GSPhotosHasMethod(configuration,@"applicationIdentifier","@16@0:8")&&
     GSPhotosHasMethod(configuration,@"clientID","@16@0:8")){
   SEL selector=NSSelectorFromString(@"applicationIdentifier");
   GSOriginalApplicationIdentifier=(void *)method_getImplementation(class_getInstanceMethod(configuration,selector));
   // AuthAdvice reads this getter after GIK configuration, including later overrides.
   class_replaceMethod(configuration,selector,(IMP)GSApplicationIdentifier,"@16@0:8");
  }
  // Optional newer SSO Objective-C entry point; absent in 7.20.2.
  Class service=NSClassFromString(@"SSOBundleIdServiceImpl");
  if(!GSOriginalSSOBundleID&&GSPhotosHasMethod(service,@"bundleId","@16@0:8")){
   SEL selector=NSSelectorFromString(@"bundleId");
   GSOriginalSSOBundleID=(void *)method_getImplementation(class_getInstanceMethod(service,selector));
   class_replaceMethod(service,selector,(IMP)GSSSOBundleID,"@16@0:8");
  }
 }
}
NSDictionary *GSSideloadIdentitySnapshot(void){
 // Status only: no installed identifier, client state, challenge, URL or credentials.
 return @{@"configurationHook":@(GSOriginalApplicationIdentifier!=NULL),
  @"bundleServiceHook":@(GSOriginalSSOBundleID!=NULL),
  @"configurationUsed":@(atomic_load(&GSApplicationIdentityUsed)),
  @"bundleServiceUsed":@(atomic_load(&GSBundleIdentityUsed)),
  @"oauth":GSOAuthDiagnosticsSnapshot()};
}
