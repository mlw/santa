/// Copyright 2016 Google Inc. All rights reserved.
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

#import "Source/santad/SNTNotificationQueue.h"
#include <Foundation/Foundation.h>

#import <dispatch/dispatch.h>
#import <MOLXPCConnection/MOLXPCConnection.h>

#include <memory>

#import "Source/common/RingBuffer.h"
#import "Source/common/SNTLogging.h"
#import "Source/common/SNTStoredEvent.h"
#import "Source/common/SNTXPCNotifierInterface.h"

static const int kMaximumNotifications = 10;

@interface SNTNotificationQueue ()
@property dispatch_queue_t pendingQueue;
@end

@implementation SNTNotificationQueue {
  std::unique_ptr<santa::RingBuffer<id>> _pendingNotifications;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _pendingQueue = dispatch_queue_create("com.northpolesec.santa.daemon.SNTNotificationQueue", DISPATCH_QUEUE_SERIAL);

    _pendingNotifications = std::make_unique<santa::RingBuffer<id>>(kMaximumNotifications);
  }
  return self;
}

- (void)addEvent:(SNTStoredEvent *)event
    withCustomMessage:(NSString *)message
            customURL:(NSString *)url
             andReply:(void (^)(BOOL authenticated))reply {
  if (!event) {
    if (reply) reply(NO);
    return;
  }

  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  [d setValue:event forKey:@"event"];
  [d setValue:message forKey:@"message"];
  [d setValue:url forKey:@"url"];
  // Copy the block to the heap so it can be called later.
  //
  // This is necessary because the block is allocated on the stack in the
  // Execution controller which goes out of scope.
  [d setValue:[reply copy] forKey:@"reply"];

  dispatch_sync(self.pendingQueue, ^{
    NSDictionary *msg = _pendingNotifications->Enqueue(d).value_or(nil);

    if (msg != nil) {
      LOGI(@"Pending GUI notification count is over %d, dropping oldest notification.", kMaximumNotifications);
      void (^replyBlock)(BOOL) = d[@"reply"];
      if (replyBlock) {
        replyBlock(NO);
      }
    }

    [self flushQueueLocked];
  });
}

- (void)flushQueueLocked {
  id rop = [self.notifierConnection remoteObjectProxy];
  if (!rop) {
    return;
  }

  while (!_pendingNotifications->Empty()) {
    NSDictionary *d = _pendingNotifications->Dequeue().value_or(nil);
    if (!d) {
      return;
    }

    [rop postBlockNotification:d[@"event"]
             withCustomMessage:d[@"message"]
                     customURL:d[@"url"]
                      andReply:d[@"reply"]];
  }
}

- (void)setNotifierConnection:(MOLXPCConnection *)notifierConnection {
  _notifierConnection = notifierConnection;
  dispatch_sync(self.pendingQueue, ^{
    [self flushQueueLocked];
  });
}

@end
