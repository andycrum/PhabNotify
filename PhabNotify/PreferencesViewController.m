//
//  PreferencesViewController.m
//  PhabNotify
//
//  Copyright (c) 2015 nortron. All rights reserved.
//

#import "PreferencesViewController.h"
#import "AppDelegate.h"
#import "PhabricatorConduit.h"

@interface PreferencesViewController ()

@end

@implementation PreferencesViewController

AppDelegate* appDelegate;
- (void)viewDidLoad {
    [super viewDidLoad];
    
    appDelegate = (AppDelegate*)[[NSApplication sharedApplication] delegate];

    NSUserDefaultsController* userDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    NSDictionary* options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"NSContinuouslyUpdatesValue"];
    [self.phabricatorUrlField bind:@"value"
                          toObject: userDefaultsController
                       withKeyPath: @"values.phabricatorUrl"
                           options: options];
    [self.conduitApiTokenField bind:@"value"
                           toObject: userDefaultsController
                        withKeyPath: @"values.conduitApiToken"
                            options: options];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    [appDelegate testConnection];
}

@end
