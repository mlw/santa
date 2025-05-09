/// Copyright 2016 Google Inc. All rights reserved.
/// Copyright 2024 North Pole Security, Inc.
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

#import "Source/santad/SNTNotificationQueue.h"
#include <_stdlib.h>
#include <libproc.h>

#import <Foundation/Foundation.h>

#include "Source/common/AuditUtilities.h"
#import "Source/common/MOLXPCConnection.h"
#import "Source/common/RingBuffer.h"
#import "Source/common/SNTLogging.h"
#import "Source/common/SNTStoredEvent.h"
#import "Source/common/SNTStrengthify.h"
#import "Source/common/SNTXPCNotifierInterface.h"
#include "absl/container/flat_hash_set.h"

@interface SNTNotificationQueue ()
@property dispatch_queue_t pendingQueue;
@property NSMutableArray *sentToUser;
@end

@implementation SNTNotificationQueue {
  std::unique_ptr<santa::RingBuffer<NSMutableDictionary *>> _pendingNotifications;
  std::unique_ptr<absl::flat_hash_set<std::pair<pid_t, int>>> _pendingProcessesToKill;
}

- (instancetype)initWithRingBuffer:
    (std::unique_ptr<santa::RingBuffer<NSMutableDictionary *>>)pendingNotifications {
  self = [super init];
  if (self) {
    _pendingNotifications = std::move(pendingNotifications);

    _pendingQueue = dispatch_queue_create("com.northpolesec.santa.daemon.SNTNotificationQueue",
                                          DISPATCH_QUEUE_SERIAL);

    _sentToUser = [NSMutableArray array];

    _pendingProcessesToKill = std::make_unique<absl::flat_hash_set<std::pair<pid_t, int>>>();
  }
  return self;
}

- (void)addEvent:(SNTStoredEvent *)event
    withCustomMessage:(NSString *)message
            customURL:(NSString *)url
          configState:(SNTConfigState *)configState
             andReply:(NotificationReplyBlock)replyBlock {
  if (!event) {
    if (replyBlock) {
      replyBlock(NO);
    }
    return;
  }

  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  [d setValue:event forKey:@"event"];
  [d setValue:message forKey:@"message"];
  [d setValue:url forKey:@"url"];
  [d setValue:configState forKey:@"config"];
  // Copy the block to the heap so it can be called later.
  // This is necessary because the block is allocated on the stack in the
  // Execution controller which goes out of scope.
  [d setValue:[replyBlock copy] forKey:@"reply"];

  dispatch_sync(self.pendingQueue, ^{
    NSDictionary *msg = _pendingNotifications->Enqueue(d).value_or(nil);

    if (msg != nil) {
      LOGI(@"Pending GUI notification count is over %zu, dropping oldest notification.",
           _pendingNotifications->Capacity());
      // Check if the dropped notification had a reply block and if so, call it
      // so any resources can be cleaned up.
      NotificationReplyBlock replyBlock = msg[@"reply"];
      if (replyBlock) {
        replyBlock(NO);
      }
    }

    [self flushQueueSerialized];
  });
}

/// For each pending notification, call the reply block if set then clear the
/// reply so it won't be called again when the notification is eventually sent.
- (void)clearAllPendingWithRepliesSerialized {
  // Auto-respond to blocks that have been sent to the UI but have not yet received a response.
  for (NSDictionary *d in self.sentToUser) {
    NotificationReplyBlock replyBlock = d[@"reply"];
    if (replyBlock) {
      replyBlock(NO);
    }
  }
  [self.sentToUser removeAllObjects];

  _pendingNotifications->Erase(
      std::remove_if(_pendingNotifications->begin(), _pendingNotifications->end(),
                     [](NSMutableDictionary *d) {
                       NotificationReplyBlock replyBlock = d[@"reply"];
                       if (replyBlock) {
                         replyBlock(NO);
                         return true;
                       } else {
                         return false;
                       }
                     }),
      _pendingNotifications->end());
}

- (void)flushQueueSerialized {
  id rop = [self.notifierConnection remoteObjectProxy];
  if (!rop) {
    // If a connection doesn't exist, clear any reply blocks in pending messages
    [self clearAllPendingWithRepliesSerialized];
    return;
  }

  while (!_pendingNotifications->Empty()) {
    NSDictionary *d = _pendingNotifications->Dequeue().value_or(nil);
    if (!d) {
      // This shouldn't ever be possible, but bail just in case.
      return;
    }

    NotificationReplyBlock replyBlock = d[@"reply"];
    if (replyBlock == nil) {
      // The reply block sent to the GUI cannot be nil. Provide one now if one was not given.
      // The copy is necessary so the block is on the heap.
      replyBlock = [^(BOOL _) {
      } copy];
    }

    // Track the object we're going to send to the user and wrap the call to
    // the replyBlock so that we can remove that object when we get a response
    // from the UI.
    // NB: It is required for this wrapped block to be called asynchronously.
    [self.sentToUser addObject:d];
    WEAKIFY(self);
    NotificationReplyBlock wrappedReplyBlock = ^(BOOL authenticated) {
      STRONGIFY(self);
      if (self) {
        dispatch_sync(self.pendingQueue, ^{
          [self.sentToUser removeObject:d];
        });
      }
      replyBlock(authenticated);
    };

    [rop postBlockNotification:d[@"event"]
             withCustomMessage:d[@"message"]
                     customURL:d[@"url"]
                   configState:d[@"config"]
                      andReply:wrappedReplyBlock];
  }
}

- (void)notifyKillOnStartup:(NSArray<SNTKillEvent*>*)events
              customMessage:(NSString*)customMessage
                  customURL:(NSString*)customURL {
  if (events.count == 0) {
    LOGD(@"Bailing because no events to send...");
    return;
  }

  id rop = [self.notifierConnection remoteObjectProxy];
  if (!rop) {
    return;
  }

  // absl::flat_hash_set<std::pair<pid_t, int>> monitoredProcs;
  for (SNTKillEvent *ke in events) {
    if (ke.gracePeriod == 0) {
      audit_token_t tok = santa::MakeStubAuditToken([ke.event.pid intValue],
        [ke.event.pidversion intValue]);
      proc_signal_with_audittoken(&tok, SIGKILL);
    } else {
      _pendingProcessesToKill->insert({[ke.event.pid intValue], [ke.event.pidversion intValue]});
    }
  }

  [rop postKillOnStartup:events customMessage:customMessage customURL:customURL];
}

- (BOOL)terminatePid:(pid_t)pid version:(int)pidversion {
  // TODO: Serialize access
  if (arc4random_uniform(2) == 1) {
    LOGE(@"Bail cause random 1...");
    return NO;
  }
  if (_pendingProcessesToKill->erase({pid, pidversion})) {
    audit_token_t tok = santa::MakeStubAuditToken(pid, pidversion);
    LOGE(@"SNTNotificationQueue terminate: %d, %d", pid, pidversion);
    // Return successfull if successfully killed or if the process is no longer running
    return (proc_signal_with_audittoken(&tok, SIGKILL) == 0 ||
      errno == ESRCH);
  } else {
    LOGE(@"SNTNotificationQueue terminate pid/pidver didn't exist: %d, %d", pid, pidversion);
    return NO;
  }
}

- (void)setNotifierConnection:(MOLXPCConnection *)notifierConnection {
  _notifierConnection = notifierConnection;

  WEAKIFY(self);
  _notifierConnection.invalidationHandler = ^{
    STRONGIFY(self);
    _notifierConnection = nil;

    // When the connection is invalidated, clear any pending notifications with reply blocks
    dispatch_sync(self.pendingQueue, ^{
      [self clearAllPendingWithRepliesSerialized];
    });
  };

  dispatch_sync(self.pendingQueue, ^{
    [self flushQueueSerialized];
  });
}

@end
