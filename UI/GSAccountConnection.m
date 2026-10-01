#import "GSAccountConnection.h"
#import "GSNativeAccount.h"
#if GS_JAILED
#import "../Jailed/DebugOverlay.h"
#endif
#import "../Shared/IPCProtocol.h"
#if !GS_JAILED
#import "GSNativeRelay.h"
#endif

static BOOL GSConnecting,GSConnected;
static NSString *GSConnectionID;
static NSTimeInterval GSLastAttempt;
static NSString *GSConnectionState=@"waiting_for_account";
static NSObject *GSConnectionLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
static void GSConnectionRecord(NSString *state){@synchronized(GSConnectionLock()){GSConnectionState=state;}}
NSDictionary *GSAccountConnectionSnapshot(void){@synchronized(GSConnectionLock()){return @{@"state":GSConnectionState};}}

static void GSConnectAvailableAccount(BOOL foreground) {
 if(!NSThread.isMainThread||GSConnecting)return;
 NSDictionary *account=GSNativeAccountSummary();NSString *identifier=account[@"identifier"];
 if(!identifier.length){
#if !GS_JAILED
  if(GSConnectionID)GSRefreshDaemonAccount();
#endif
  GSConnectionID=nil;GSConnected=NO;GSConnectionRecord(@"waiting_for_account");return;
 }
 BOOL changed=![identifier isEqual:GSConnectionID];
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
 // Poll metadata until SSO is ready. Once connected, ordinary ticks do no RPC.
 // Failed attempts are bounded; repeated foreground notifications are coalesced.
 if(!changed&&((!foreground&&GSConnected)||now-GSLastAttempt<(foreground?5:60)))return;
 GSConnectionID=identifier;GSLastAttempt=now;GSConnecting=YES;GSConnected=NO;GSConnectionRecord(@"connecting");
#if GS_JAILED
 GSDebugSetStatus(@"native account connection: connecting");
#endif
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
  NSError *error=nil;BOOL success=NO;
#if GS_JAILED
  success=GSRequest(@{@"op":@"account_native",@"account":account[@"email"],@"nativeID":identifier},&error)!=nil;
#else
  success=GSConnectDaemonAccount(account,&error);
#endif
  dispatch_async(dispatch_get_main_queue(),^{
   GSConnecting=NO;
   if(![GSNativeAccountSummary()[@"identifier"]isEqual:identifier]){
    GSConnectionID=nil;GSConnected=NO;GSConnectionRecord(@"waiting_for_account");return;
   }
   GSConnected=success;
if (success) {
 GSConnectionRecord(@"connected");
#if GS_JAILED
 GSDebugSetStatus(@"native account connection: SUCCESS");
#endif
} else {
 NSString *domain=error.domain ?: @"unknown";
 NSInteger code=error.code;
 NSString *trace=[NSString stringWithFormat:@"native account connection: FAILED %@/%ld",domain,(long)code];
 GSConnectionRecord(trace);
#if GS_JAILED
 GSDebugSetStatus(trace);
#endif
}
  });
 }});
}
void GSStartAccountConnection(void) {
 if(!NSThread.isMainThread)return;
 static dispatch_once_t once;dispatch_once(&once,^{
  GSInstallNativeAccount();
  [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){GSConnectAvailableAccount(NO);}];
 });
 GSConnectAvailableAccount(NO);
}
void GSResumeAccountConnection(void){GSConnectAvailableAccount(YES);}

