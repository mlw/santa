/// Copyright 2015 Google Inc. All rights reserved.
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

#import "Source/common/SNTXPCNotifierInterface.h"

#import "Source/common/SNTStoredEvent.h"

@implementation SNTXPCNotifierInterface

+ (NSXPCInterface *)notifierInterface {
  NSXPCInterface *r = [NSXPCInterface interfaceWithProtocol:@protocol(SNTNotifierXPC)];

  [r setClasses:[NSSet setWithObjects:[NSArray class], [SNTKillEvent class], nil]
        forSelector:@selector(postKillOnStartup:customMessage:customURL:)
      argumentIndex:0
            ofReply:NO];

  return r;
}

@end
