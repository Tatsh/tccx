//
//     Generated by class-dump 3.5 (64 bit).
//
//     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2015 by Steve Nygard.
//

#import "TCCDPlatform.h"

@class TCCDAdhocSignatureCache;

@interface TCCDPlatformMacOS : TCCDPlatform {
    TCCDAdhocSignatureCache *_adhocSignatureCache;
}

+ (BOOL)deriveIsPlatformBinary:(id)arg1 withCodesignFlags:(unsigned int)arg2;
- (id)_clientIdentifierFromCopyInformationMessage:(id)arg1;
- (void)_configureServices;
- (id)_connectionForTargetTCCD:(unsigned int)arg1;
- (BOOL)_shouldUnsignedBundleIdentifierBeDenied:(id)arg1
                                  staticCodeRef:(struct __SecCode *)arg2;
- (int)adhocSignStaticCode:(struct __SecCode *)arg1;
- (id)appBundleURLContainingExecutableURL:(id)arg1;
- (id)codeRequirementForIdentifyingUnsignedCode;
- (id)codeRequirementFromStaticCode:(struct __SecCode *)arg1;
- (id)createAdhocSignatureForStaticCode:(struct __SecCode *)arg1;
- (long long)evaluatePolicyForPromptingforService:(id)arg1
                                       byIdentity:(id)arg2
                                 attributionChain:(id)arg3;
- (void)forwardMessage:(id)arg1
    toUserTCCDFromAttributionChain:(id)arg2
                        forService:(id)arg3
                 andMergeReplyInto:(id)arg4
                    forConnnection:(id)arg5;
- (void)handleCompositionType:(long long)arg1
             forParentService:(id)arg2
                   forRequest:(id)arg3
                    intoReply:(id)arg4;
- (id)homeRelativePathToDatabase;
- (id)initWithName:(id)arg1;
- (void)notifyUserOfDeniedAccessBy:(id)arg1 forService:(id)arg2;
- (void)runBacktraceToolOnTask:(struct __SecTask *)arg1
                       withPID:(int)arg2
                    forService:(id)arg3;
- (BOOL)sendMessageAsync:(id)arg1
      toTCCDForTargetUID:(unsigned int)arg2
          withReplyBlock:(CDUnknownBlockType)arg3;
- (id)sendMessageSync:(id)arg1 toTCCDForTargetUID:(unsigned int)arg2;
- (void)setupAdhocSignatureCache;
- (BOOL)shouldUnsignedCodeBeDenied:(struct __SecCode *)arg1;
- (BOOL)shouldUnsignedIdentityBeDenied:(id)arg1;
- (id)stateDirectory;
- (id)stringFromCodeRequirementData:(id)arg1;
- (void)updateAnalyticsEvent:(id)arg1 fromIdentity:(id)arg2 keyPrefix:(id)arg3;

@end
