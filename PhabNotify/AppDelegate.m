//
//  AppDelegate.m
//  PhabNotify
//
//  Copyright (c) 2015 nortron. All rights reserved.
//

#import "AppDelegate.h"
#import "PreferencesViewController.h"
#import "PhabricatorConduit.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

// interface
NSStatusItem *statusItem;
NSPopover* popover = nil;
bool showingPreferences = false;
PreferencesViewController* preferencesController = nil;
id mouseEventMonitor = nil;

// api data
PhabricatorConduit* conduit;
NSTimer* updatesTimer = nil;
bool updatingDiffList = false;
bool lookingForDiffChanges = false;
NSString* conduitPhid;
NSString* conduitUsername;
NSString* conduitRealName;
NSMutableDictionary* knownDiffs;
NSString* lastSeenFeedID;

- (void)applicationDidFinishLaunching:(NSNotification *)appNotification {
    // sign up for notifications
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    
    // set up our status item
    NSString* iconPath = @"phab-menu-icon";
    NSImage* statusIcon = [NSImage imageNamed:iconPath];
    [statusIcon setTemplate:YES];
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setImage:statusIcon];
    [statusItem.button setAction:@selector(statusItemClicked:)];

    // set up popover for configuration
    popover = [[NSPopover alloc] init];
    [popover setBehavior: NSPopoverBehaviorApplicationDefined];
    //    [popover setDelegate: self];
    preferencesController = [[PreferencesViewController alloc] initWithNibName:@"PreferencesViewController" bundle:nil];
    [popover setContentViewController: preferencesController];
    [popover setContentSize: preferencesController.view.frame.size];

    // handle loading from a notification click
    NSUserNotification *userNotification = appNotification.userInfo[NSApplicationLaunchUserNotificationKey];
    if (userNotification) {
        [self respondToNotificationActivation:userNotification];
    }
    
    conduit = [[PhabricatorConduit alloc] init];

    [self testConnection];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    [self respondToNotificationActivation:notification];
}

- (void)respondToNotificationActivation:(NSUserNotification *)notification {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:notification.userInfo[@"url"]]];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)c shouldPresentNotification:(NSUserNotification *)n {
    return YES;
}

- (void)sendNotificationWithTitle:(NSString*)title Details:(NSString*)details UserInfo:(NSDictionary*)userInfo {
    NSUserNotification *notification = [NSUserNotification new];
    notification.title = title; // ellipsis after 48
    notification.informativeText = details; // ellipsis after 60
    notification.deliveryDate = [NSDate dateWithTimeIntervalSinceNow:0];
    notification.userInfo = userInfo;
    [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:notification];
}

- (void)statusItemClicked:(id)sender {
    NSEvent* event = [NSApp currentEvent];
    if ([event modifierFlags] & NSCommandKeyMask) {
        [[NSApplication sharedApplication] terminate:self];
        return;
    }
    
    [self togglePreferences:sender];
}

- (void)togglePreferences:(id)sender {
    if (showingPreferences) {
        [mouseEventMonitor invalidate];
        [popover performClose: sender];
    } else {
        [popover showRelativeToRect: statusItem.button.bounds ofView: statusItem.button preferredEdge: NSMinYEdge];
        NSEventMask allMouseClicks = NSLeftMouseDownMask | NSRightMouseDownMask | NSOtherMouseDownMask;
        mouseEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:allMouseClicks handler:^(NSEvent *event){
            [self togglePreferences:nil];
        }];
    }
    
    showingPreferences = !showingPreferences;
}

- (void)testConnection {
    bool connected = [self loadUserInfo];
    if (connected) {
        [preferencesController.statusLabel setStringValue:[NSString stringWithFormat:@"Connected as %@", conduitRealName]];
        [preferencesController.statusLabel setTextColor:[NSColor blackColor]];
        
        [self intializeKnownDiffs];
        
        updatesTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(lookForUpdates) userInfo:nil repeats:true];
    } else {
        if (updatesTimer) {
            [updatesTimer invalidate];
        }
        
        [preferencesController.statusLabel setStringValue:@"Not connected"];
        [preferencesController.statusLabel setTextColor:[NSColor redColor]];
        
        if (!showingPreferences) {
            [self togglePreferences:nil];
        }
    }
}

- (void)lookForUpdates {
    [self updateDiffList];
    [self lookForDiffChanges];
}

- (bool)loadUserInfo {
    NSError* error = nil;
    id object = [conduit request:@"user.whoami" data:@"" error:&error];
    if(error) {
        return false;
    }
    
    if(![object isKindOfClass:[NSDictionary class]]) {
        return false;
    }

    NSDictionary *results = object;
    conduitPhid = results[@"phid"];
    conduitUsername = results[@"userName"];
    conduitRealName = results[@"realName"];
    
    return true;
}

- (NSArray*)getOpenDiffs {
    NSError* error = nil;
    id object = [conduit request:@"differential.query" data:@"status=status-open" error:&error];
    if(error) {
        return nil;
    }
    
    if(![object isKindOfClass:[NSArray class]])
    {
        return nil;
    }

    return object;
}

- (void)intializeKnownDiffs {
    knownDiffs = [[NSMutableDictionary alloc] init];

    NSArray* openDiffs = [self getOpenDiffs];
    for (NSDictionary* diff in openDiffs) {
        [knownDiffs setObject:diff forKey:diff[@"phid"]];
    }
}

- (void)updateDiffList {
    if (updatingDiffList) {
        return;
    }
    
    updatingDiffList = true;
    
    NSMutableDictionary* latestDiffs = [[NSMutableDictionary alloc] init];
    NSArray* openDiffs = [self getOpenDiffs];
    if (!openDiffs) {
        updatingDiffList = false;
        return;
    }
    
    for (NSDictionary* diff in openDiffs) {
        [latestDiffs setObject:diff forKey:diff[@"phid"]];
        
        [self testForCreatedDiff:diff];
        [self testForAcceptedDiff:diff];
    }
    
    knownDiffs = latestDiffs;
    updatingDiffList = false;
}

- (void)lookForDiffChanges {
    if (lookingForDiffChanges) {
        return;
    }
    
    lookingForDiffChanges = true;
    
    // prob less than 10 changes per refresh
    NSString* requestData = @"limit=10";
    
    int index = 0;
    for (NSString* key in knownDiffs) {
        if (![knownDiffs[key][@"authorPHID"] isEqualToString:conduitPhid]) {
            continue;
        }
        
        // only look for changes to our own diffs
        requestData = [NSString stringWithFormat:@"%@&filterPHIDs[%d]=%@", requestData, index, key];
        index++;
    }
    
    // we have no open diffs
    if (index == 0) {
        lookingForDiffChanges = false;
        return;
    }
    
    NSError* error = nil;
    id object = [conduit request:@"feed.query" data:requestData error:&error];
    if(error) {
        lookingForDiffChanges = false;
        return;
    }
    
    if([object isKindOfClass:[NSArray class]])
    {
        // no results
        lookingForDiffChanges = false;
        return;
    }
    
    // restore chronological sorting
    NSDictionary* feed = object;
    NSArray* sortedKeys = [feed keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDictionary* dict1 = obj1;
        NSDictionary* dict2 = obj2;
        NSComparisonResult res = [dict1[@"chronologicalKey"] compare:dict2[@"chronologicalKey"] options:NSNumericSearch];
        
        return res;
    }];
    
    if (!lastSeenFeedID) {
        // first feed call
        NSString* firstKey = [[sortedKeys reverseObjectEnumerator] nextObject];
        NSDictionary* firstItem = feed[firstKey];
        lastSeenFeedID = firstItem[@"chronologicalKey"];
        lookingForDiffChanges = false;
        
        return;
    }
    
    NSString* latestSeenFeedID = nil;
    for (NSString* key in [sortedKeys reverseObjectEnumerator]) {
        NSDictionary* event = feed[key];
        if ([event[@"chronologicalKey"] isEqualToString:lastSeenFeedID]) {
            break;
        }
        
        if (!latestSeenFeedID) {
            latestSeenFeedID = event[@"chronologicalKey"];
        }
        
        [self testForReviewedEvent:event];
    }
    
    if (latestSeenFeedID) {
        lastSeenFeedID = latestSeenFeedID;
    }
    
    lookingForDiffChanges = false;
}

- (void)testForCreatedDiff:(NSDictionary*) diff {
    if ([knownDiffs objectForKey:diff[@"phid"]] != nil) {
        // already exists
        return;
    }

    if ([diff[@"authorPHID"] isEqualToString:conduitPhid]) {
        // created by this user
        return;
    }
    
    NSError* error;
    NSDictionary* user = [conduit getUserByPhid:diff[@"authorPHID"] Error:&error];
    if (error) {
        // networking error
        return;
    }
    
    if (!user) {
        // failed to look up user info
        return;
    }
    
    NSString* title = [NSString stringWithFormat:@"New diff from %@: D%@", user[@"userName"], diff[@"id"]];
    NSString* details = [NSString stringWithFormat:@"%@", diff[@"title"]];
    NSDictionary* userInfo = @{@"url": diff[@"uri"]};
    [self sendNotificationWithTitle:title Details:details UserInfo:userInfo];
}

- (void)testForAcceptedDiff:(NSDictionary*) diff {
    if ([knownDiffs objectForKey:diff[@"phid"]] == nil) {
        // new diff
        return;
    }
    
    if (![diff[@"authorPHID"] isEqualToString:conduitPhid]) {
        // not created by this user
        return;
    }
    
    if ([[knownDiffs[diff[@"phid"]] objectForKey:@"statusName"] isEqualToString:@"Accepted"]) {
        // already accepted
        return;
    }
    
    if (![[diff objectForKey:@"statusName"] isEqualToString:@"Accepted"]) {
        // not entering accepted status
        return;
    }
    
    NSString* title = [NSString stringWithFormat:@"D%@ was accepted", diff[@"id"]];
    NSString* details = [NSString stringWithFormat:@"%@", diff[@"title"]];
    NSDictionary* userInfo = @{@"url": diff[@"uri"]};
    [self sendNotificationWithTitle:title Details:details UserInfo:userInfo];
}

- (void)testForReviewedEvent: (NSDictionary*)event {
    if ([event[@"authorPHID"] isEqualToString:conduitPhid]) {
        // current user performed action
        return;
    }
    
    NSDictionary* diff = [knownDiffs objectForKey:event[@"data"][@"objectPHID"]];
    if (!diff) {
        // not an object we care about
        return;
    }
    
    if ([diff[@"statusName"] isEqualToString:@"Accepted"]) {
        // skip accepted
        return;
    }
    
    NSError* error = nil;
    NSDictionary* user = [conduit getUserByPhid:event[@"authorPHID"] Error:&error];
    if (error) {
        return;
    }
    
    if (!user) {
        return;
    }
    
    NSString* title = [NSString stringWithFormat:@"%@ reviewed D%@", user[@"userName"], diff[@"id"]];
    NSString* details = diff[@"title"];
    NSDictionary* userInfo = @{@"url": diff[@"uri"]};
    [self sendNotificationWithTitle:title Details:details UserInfo:userInfo];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

@end
