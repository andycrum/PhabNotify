//
//  PhabricatorConduit.h
//  PhabNotify
//
//  Copyright (c) 2015 nortron. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PhabricatorConduit : NSObject

- (id)request: (NSString*)endpoint data: (NSString*)data error: (NSError**)error;

@end
