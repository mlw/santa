/// Copyright 2015 Google Inc. All rights reserved.
/// Copyright 2024 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import <Cocoa/Cocoa.h>

#import "Source/common/SNTConfigState.h"
#import "Source/gui/SNTMessageWindowController.h"

@class SNTStoredExecutionEvent;
@class SNTBundleProgress;

///
///  Controller for a single message window.
///
@interface SNTBinaryMessageWindowController : SNTMessageWindowController

- (instancetype)initWithEvent:(SNTStoredExecutionEvent *)event
                    customMsg:(NSString *)message
                    customURL:(NSString *)url
                  configState:(SNTConfigState *)configState
                        reply:(void (^)(BOOL authenticated))replyBlock;

- (void)updateBlockNotification:(SNTStoredExecutionEvent *)event
                 withBundleHash:(NSString *)bundleHash;

///  Reference to the "Bundle Hash" label in the XIB. Used to remove if application
///  doesn't have a bundle hash.
@property(weak) IBOutlet NSTextField *bundleHashLabel;

///  Reference to the "Bundle Identifier" label in the XIB. Used to remove if application
///  doesn't have a bundle hash.
@property(weak) IBOutlet NSTextField *bundleHashTitle;

///
/// Is displayed if calculating the bundle hash is taking a bit.
///
@property(readonly) SNTBundleProgress *bundleProgress;

///
/// Snapshot of configuration used for processing the event.
///
@property(readonly) SNTConfigState *configState;

///
///  The execution event that this window is for
///
@property(readonly) SNTStoredExecutionEvent *event;

///
///  The reply block to call when the user has made a decision in standalone
///  mode.
@property(readonly, nonatomic) void (^replyBlock)(BOOL authenticated);

///
///  The root progress object. Child nodes are vended to santad to report on work being done.
///
@property NSProgress *progress;

@end
