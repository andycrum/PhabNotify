//
//  PreferencesViewController.h
//  PhabNotify
//
//  Copyright (c) 2015 nortron. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PreferencesViewController : NSViewController

@property (readwrite, retain) IBOutlet NSTextField* phabricatorUrlField;
@property (readwrite, retain) IBOutlet NSTextField* conduitApiTokenField;
@property (readwrite, retain) IBOutlet NSTextField* statusLabel;

@end
