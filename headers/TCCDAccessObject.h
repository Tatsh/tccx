//
//     Generated by class-dump 3.5 (64 bit).
//
//     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2015 by Steve Nygard.
//

#import <objc/NSObject.h>

@class TCCDAccessIndirectObject, TCCDService;

@interface TCCDAccessObject : NSObject {
    TCCDService *_serviceObject;
    TCCDAccessIndirectObject *_indirectObject;
}

- (id)description;
@property (retain) TCCDAccessIndirectObject *indirectObject;
- (id)initWithService:(id)arg1 indirectObject:(id)arg2;
@property (retain) TCCDService *serviceObject;

@end