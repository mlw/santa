/// Copyright 2023 Google LLC
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

#import <Cocoa/Cocoa.h>

#import "Source/gui/SNTMessageWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@class SNTConfigState;
@class SNTStoredFileAccessEvent;

///
///  Controller for a single message window.
///
@interface SNTFileAccessMessageWindowController : SNTMessageWindowController <NSWindowDelegate>

- (instancetype)initWithEvent:(SNTStoredFileAccessEvent *)event
                customMessage:(nullable NSString *)message
                    customURL:(nullable NSString *)url
                   customText:(nullable NSString *)text
                  configState:(nullable SNTConfigState *)configState;

@property(readonly) SNTStoredFileAccessEvent *event;

@end

NS_ASSUME_NONNULL_END
