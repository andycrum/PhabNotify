//
//  PhabricatorConduit.m
//  PhabNotify
//
//  Copyright (c) 2015 nortron. All rights reserved.
//

#import "PhabricatorConduit.h"

@implementation PhabricatorConduit

- (id)request: (NSString*)endpoint data: (NSString*)data error: (NSError**)error {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* phabricatorUrl = [userDefaults objectForKey:@"phabricatorUrl"];
    NSString* conduitApiToken = [userDefaults objectForKey:@"conduitApiToken"];
    
    NSURL *url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@/api/%@", phabricatorUrl, endpoint]];
    NSString *postString = [NSString stringWithFormat:@"api.token=%@&%@", conduitApiToken, data];
    NSData *postData = [postString dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *postLength = [NSString stringWithFormat:@"%lu",[postData length]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    NSURLResponse *response = nil;
    NSData *rawData = [NSURLConnection sendSynchronousRequest: request returningResponse: &response error: error];
    if (*error) {
        return nil;
    }
    
    id object = [NSJSONSerialization JSONObjectWithData:rawData options:0 error:error];
    if(*error) {
        return nil;
    }
    
    if(![object isKindOfClass:[NSDictionary class]])
    {
        return nil;
    }
    
    NSDictionary* responseObject = object;
    
    return responseObject[@"result"];
}

- (NSDictionary*)getUserByPhid: (NSString*)phid Error: (NSError**)error {
    id object = [self request:@"user.query" data:[NSString stringWithFormat:@"phids[0]=%@", phid] error:error];
    
    if(*error) {
        return nil;
    }
    
    if(![object isKindOfClass:[NSArray class]])
    {
        return nil;
    }
    
    NSArray *results = object;
    return [results objectAtIndex:0];
}

@end
