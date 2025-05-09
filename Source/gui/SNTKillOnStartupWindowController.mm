/// Copyright 2025 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     https://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

#import "Source/gui/SNTKillOnStartupWindowController.h"
#import "Source/gui/SNTKillOnStartupWindowView-Swift.h"

#include <AppKit/AppKit.h>
#include <dispatch/dispatch.h>

#import "Source/common/SNTBlockMessage.h"
#import "Source/common/SNTConfigurator.h"
#import "Source/common/SNTStoredEvent.h"
#import "Source/common/SNTXPCControlInterface.h"
#import "Source/common/MOLXPCConnection.h"

@interface SNTKillOnStartupWindowController ()

///
///  The processes that must be terminated
///
@property(readonly) NSArray<SNTKillEvent *> *events;

///  The custom message to display for this event
@property(copy) NSString *customMessage;

///  The custom URL to use for this event
@property(copy) NSString *customURL;

@property MOLXPCConnection *daemonConn;

@end

@implementation SNTKillOnStartupWindowController

- (instancetype)initWithEvents:(NSArray<SNTKillEvent *> *)events
                     customMsg:(NSString *)message
                     customURL:(NSString *)url {
  self = [super init];
  if (self) {
    _events = events;
    _customMessage = message;
    _customURL = url;

    _daemonConn = [SNTXPCControlInterface configuredConnection];
    [_daemonConn resume];
  }
  return self;
}

- (void)dealloc {
  [self.daemonConn invalidate];
}

- (void)windowDidResize:(NSNotification *)notification {
  [self.window center];
}

- (void)showWindow:(id)sender {
  if (self.window) [self.window orderOut:sender];

  for (SNTKillEvent *ke in self.events) {
    NSLog(@"Looking at ke: %@ (%@, %@), idx: %@", ke.event.signingID, ke.event.pid, ke.event.pidversion, ke.event.idx);
  }

  self.window =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 0, 0)
                                  styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskResizable |
                                            NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  self.window.titlebarAppearsTransparent = YES;
  self.window.movableByWindowBackground = YES;
  [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
  [self.window standardWindowButton:NSWindowCloseButton].hidden = YES;
  [self.window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
  self.window.contentViewController = [SNTKillOnStartupWindowViewFactory
      createWithWindow:self.window
                 events:self.events
             customMsg:self.customMessage
             customURL:self.customURL
             // terminateProcessCallback:self.terminateProcessCallback];
             // terminateProcessCallback:^(pid_t pid, int pidver) {
             //    NSLog(@"CLICKED BUTTON! Pid: %d, pidver: %d", pid, pidver);
             // }];
             terminateProcessCallback:^BOOL(NSNumber *pid, NSNumber * pidver) {
                NSLog(@"CLICKED BUTTON! Pid: %@, pidver: %@", pid, pidver);
                __block BOOL success;
                [[self.daemonConn synchronousRemoteObjectProxy] terminatePid:[pid intValue] version:[pidver intValue] reply:^(BOOL value) {
                  NSLog(@"In controller got result: %d", value);
                  success = value;
                }];
                NSLog(@"Returning value to swift: %d", success);
                return success;
             }];

  self.window.delegate = self;

  [super showWindow:sender];
}

- (NSString *)messageHash {
  return self.events[0].event.cdhash;
}

@end
