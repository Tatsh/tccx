//
//     Generated by class-dump 3.5 (64 bit).
//
//     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2015 by Steve Nygard.
//

#import <objc/NSObject.h>

@class TCCDPlatform;
@protocol OS_dispatch_source
, OS_os_log;

@interface TCCDServer : NSObject {
    BOOL _macos_isSystemServer;
    BOOL _allowsInternalSecurityPolicies;
    BOOL _testDoComposition;
    BOOL _generateBacktraceOnPrompt;
    TCCDPlatform *_platform;
    NSObject<OS_os_log> *_logHandle;
    NSObject<OS_dispatch_source> *_macos_compatibilityFileVnodeSource;
}

- (id)accessRecordFromStep:(struct sqlite3_stmt *)arg1;
@property BOOL allowsInternalSecurityPolicies;
- (void)buildErrorString:(id)arg1 forError:(id)arg2 contextString:(id)arg3;
- (BOOL)canProcess:(id)arg1 manageService:(id)arg2;
- (void)createStateHandler;
- (id)descriptionDictionariesForAllAccessRecords;
- (id)descriptionForMessage:(id)arg1;
- (BOOL)evaluateAccessToService:(id)arg1
             defaultAccessAllowed:(BOOL)arg2
                               by:(id)arg3
            checkCodeRequirements:(BOOL)arg4
              authorizationResult:(unsigned long long *)arg5
    subjectCodeIdentityDataResult:(id *)arg6;
- (BOOL)evaluateComposedAuthoriationToService:(id)arg1
                             andAccessSubject:(id)arg2
                                 withRelation:(long long)arg3
                          authorizationResult:(unsigned long long *)arg4
                subjectCodeIdentityDataResult:(id *)arg5;
- (void)evaluateForProcess:(id)arg1
           entitlementName:(id)arg2
           containsService:(id)arg3
                   options:(unsigned long long)arg4
       authorizationResult:(unsigned long long *)arg5;
- (BOOL)
    evaluateUserIndependentEntitlementsForAccessByAttributionChain:(id)arg1
                                                         toService:(id)arg2
                                               authorizationResult:
                                                   (unsigned long long *)arg3
                                                             error:(id *)arg4;
- (id)fetchAllAccessRecords;
- (id)fetchAllActivePolicies;
- (id)fetchAllOverridenServiceNames;
- (id)fetchAllPolicies;
@property BOOL generateBacktraceOnPrompt;
- (BOOL)getInternalBoolPreference:(id)arg1;
- (id)init;
- (BOOL)isAccessEntryWithAge:(int)arg1
          authorizationValue:(unsigned long long)arg2
           expiredForService:(id)arg3;
- (BOOL)isProcessServiceCompositionManager:(id)arg1;
@property (retain) NSObject<OS_os_log> *logHandle;
@property (retain)
    NSObject<OS_dispatch_source> *macos_compatibilityFileVnodeSource;
@property BOOL macos_isSystemServer;
- (void)makeError:(id *)arg1 withCode:(long long)arg2 infoText:(id)arg3;
@property (retain, nonatomic) TCCDPlatform *platform;
- (void)purgeAllExpiredAccessEntries;
- (void)purgeExpiredAccessEntriesForService:(id)arg1;
- (id)recordFromMessage:(id)arg1 accessIdentity:(id)arg2 error:(id *)arg3;
- (void)scheduleAccessEntryExpiryCheckForService:(id)arg1;
- (id)serviceFromMessage:(id)arg1 error:(id *)arg2;
@property BOOL testDoComposition;
- (id)stateDumpDictionary;
- (id)stringFromErrorCode:(long long)arg1;
- (BOOL)targetAuditToken:(CDStruct_4c969caf *)arg1
             fromMessage:(id)arg2
                   error:(id *)arg3;
- (BOOL)updateAccessRecord:(id)arg1
                      replaceOnly:(BOOL)arg2
    doCompositionWithChildService:(BOOL)arg3;

@end
