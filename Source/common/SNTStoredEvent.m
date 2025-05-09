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

#import "Source/common/SNTStoredEvent.h"

#import "Source/common/CertificateHelpers.h"
#import "Source/common/CoderMacros.h"
#import "Source/common/MOLCertificate.h"
#import "Source/common/SNTLogging.h"

@implementation SNTKillEvent
+ (BOOL)supportsSecureCoding {
  return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  ENCODE_BOXABLE(coder, gracePeriod);
  ENCODE(coder, event);
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [super init];
  if (self) {
    DECODE_SELECTOR(decoder, gracePeriod, NSNumber, integerValue);
    DECODE(decoder, event, SNTStoredEvent);
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  LOGE(@"KE Copy with zone...");
  SNTKillEvent *copy = [[[self class] allocWithZone:zone] init];
  copy.gracePeriod = self.gracePeriod;
  copy.event = [self.event copyWithZone:zone];
  return copy;
}

@end

@implementation SNTStoredEvent

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  ENCODE(coder, idx);
  ENCODE(coder, fileSHA256);
  ENCODE(coder, filePath);

  ENCODE_BOXABLE(coder, needsBundleHash);
  ENCODE(coder, fileBundleHash);
  ENCODE(coder, fileBundleHashMilliseconds);
  ENCODE(coder, fileBundleBinaryCount);
  ENCODE(coder, fileBundleName);
  ENCODE(coder, fileBundlePath);
  ENCODE(coder, fileBundleExecutableRelPath);
  ENCODE(coder, fileBundleID);
  ENCODE(coder, fileBundleVersion);
  ENCODE(coder, fileBundleVersionString);

  ENCODE(coder, signingChain);
  ENCODE(coder, teamID);
  ENCODE(coder, signingID);
  ENCODE(coder, cdhash);
  ENCODE_BOXABLE(coder, codesigningFlags);
  ENCODE_BOXABLE(coder, signingStatus);
  ENCODE(coder, entitlements);
  ENCODE_BOXABLE(coder, entitlementsFiltered);

  ENCODE(coder, executingUser);
  ENCODE(coder, occurrenceDate);
  ENCODE_BOXABLE(coder, decision);
  ENCODE(coder, pid);
  ENCODE(coder, pidversion);
  ENCODE(coder, ppid);
  ENCODE(coder, parentName);

  ENCODE(coder, loggedInUsers);
  ENCODE(coder, currentSessions);

  ENCODE(coder, quarantineDataURL);
  ENCODE(coder, quarantineRefererURL);
  ENCODE(coder, quarantineTimestamp);
  ENCODE(coder, quarantineAgentBundleID);
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _idx = @(arc4random());
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  self = [super init];
  if (self) {
    DECODE(decoder, idx, NSNumber);
    DECODE(decoder, fileSHA256, NSString);
    DECODE(decoder, filePath, NSString);

    DECODE_SELECTOR(decoder, needsBundleHash, NSNumber, boolValue);
    DECODE(decoder, fileBundleHash, NSString);
    DECODE(decoder, fileBundleHashMilliseconds, NSNumber);
    DECODE(decoder, fileBundleBinaryCount, NSNumber);
    DECODE(decoder, fileBundleName, NSString);
    DECODE(decoder, fileBundlePath, NSString);
    DECODE(decoder, fileBundleExecutableRelPath, NSString);
    DECODE(decoder, fileBundleID, NSString);
    DECODE(decoder, fileBundleVersion, NSString);
    DECODE(decoder, fileBundleVersionString, NSString);

    DECODE_ARRAY(decoder, signingChain, MOLCertificate);
    DECODE(decoder, teamID, NSString);
    DECODE(decoder, signingID, NSString);
    DECODE(decoder, cdhash, NSString);
    DECODE_SELECTOR(decoder, codesigningFlags, NSNumber, unsignedIntValue);
    DECODE_SELECTOR(decoder, signingStatus, NSNumber, integerValue);
    DECODE_DICT(decoder, entitlements);
    DECODE_SELECTOR(decoder, entitlementsFiltered, NSNumber, boolValue);

    DECODE(decoder, executingUser, NSString);
    DECODE(decoder, occurrenceDate, NSDate);
    DECODE_SELECTOR(decoder, decision, NSNumber, unsignedLongLongValue);
    DECODE(decoder, pid, NSNumber);
    DECODE(decoder, pidversion, NSNumber);
    DECODE(decoder, ppid, NSNumber);
    DECODE(decoder, parentName, NSString);

    DECODE_ARRAY(decoder, loggedInUsers, NSString);
    DECODE_ARRAY(decoder, currentSessions, NSString);

    DECODE(decoder, quarantineDataURL, NSString);
    DECODE(decoder, quarantineRefererURL, NSString);
    DECODE(decoder, quarantineTimestamp, NSDate);
    DECODE(decoder, quarantineAgentBundleID, NSString);
  }
  return self;
}

- (BOOL)isEqual:(id)other {
  if (other == self) return YES;
  if (![other isKindOfClass:[SNTStoredEvent class]]) return NO;
  SNTStoredEvent *o = other;
  return ([self.fileSHA256 isEqual:o.fileSHA256] && [self.idx isEqual:o.idx]);
}

- (NSUInteger)hash {
  NSUInteger prime = 31;
  NSUInteger result = 1;
  result = prime * result + [self.idx hash];
  result = prime * result + [self.fileSHA256 hash];
  result = prime * result + [self.occurrenceDate hash];
  return result;
}

- (NSString *)description {
  return
      [NSString stringWithFormat:@"SNTStoredEvent[%@] with SHA-256: %@", self.idx, self.fileSHA256];
}

- (NSString *)publisherInfo {
  return Publisher(self.signingChain, self.teamID);
}

- (NSArray *)signingChainCertRefs {
  return CertificateChain(self.signingChain);
}

- (id)copyWithZone:(NSZone *)zone {
  LOGE(@"StoredEvent Copy with zone...");
  SNTStoredEvent *copy = [[[self class] allocWithZone:zone] init];

  copy.idx = @(arc4random());
  copy.fileSHA256 = [self.fileSHA256 copyWithZone:zone];

  copy.filePath = [self.filePath copyWithZone:zone];
  copy.needsBundleHash = self.needsBundleHash;
  copy.fileBundleHash = [self.fileBundleHash copyWithZone:zone];
  copy.fileBundleHashMilliseconds = [self.fileBundleHashMilliseconds copyWithZone:zone];
  copy.fileBundleBinaryCount = [self.fileBundleBinaryCount copyWithZone:zone];
  copy.fileBundleName = [self.fileBundleName copyWithZone:zone];
  copy.fileBundlePath = [self.fileBundlePath copyWithZone:zone];
  copy.fileBundleExecutableRelPath = [self.fileBundleExecutableRelPath copyWithZone:zone];
  copy.fileBundleID = [self.fileBundleID copyWithZone:zone];
  copy.fileBundleVersion = [self.fileBundleVersion copyWithZone:zone];
  copy.fileBundleVersionString = [self.fileBundleVersionString copyWithZone:zone];
  LOGE(@"Copy with zone: signing chain");
  copy.signingChain = [self.signingChain sntDeepCopy];
  copy.teamID = [self.teamID copyWithZone:zone];
  copy.signingID = [self.signingID copyWithZone:zone];
  copy.cdhash = [self.cdhash copyWithZone:zone];
  copy.codesigningFlags = self.codesigningFlags;
  copy.signingStatus = self.signingStatus;
  copy.executingUser = [self.executingUser copyWithZone:zone];
  copy.occurrenceDate = [self.occurrenceDate copyWithZone:zone];
  copy.decision = self.decision;
  LOGE(@"Copy with zone: logged in users");
  copy.loggedInUsers = [self.loggedInUsers sntDeepCopy];
    LOGE(@"Copy with zone: current sessions");
  copy.currentSessions = [self.currentSessions sntDeepCopy];
  copy.pid = [self.pid copyWithZone:zone];
  copy.pidversion = [self.pidversion copyWithZone:zone];
  copy.ppid = [self.ppid copyWithZone:zone];
  copy.parentName = [self.parentName copyWithZone:zone];
  copy.quarantineDataURL = [self.quarantineDataURL copyWithZone:zone];
  copy.quarantineRefererURL = [self.quarantineRefererURL copyWithZone:zone];
  copy.quarantineTimestamp = [self.quarantineTimestamp copyWithZone:zone];
  copy.quarantineAgentBundleID = [self.quarantineAgentBundleID copyWithZone:zone];
  // copy.publisherInfo = [self.publisherInfo copyWithZone:zone];
  // copy.signingChainCertRefs = [self.signingChainCertRefs copyWithZone:zone];
  LOGE(@"Copy with zone: entitlements");
  copy.entitlements = [self.entitlements sntDeepCopy];
  copy.entitlementsFiltered = self.entitlementsFiltered;

  return copy;
}

@end
