/// Copyright 2023 Google LLC
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

#import "Source/common/CertificateHelpers.h"
#import "Source/common/MOLCertificate.h"
#import "Source/common/MOLCodesignChecker.h"

#include <Security/SecCertificate.h>

NSString *Publisher(NSArray<MOLCertificate *> *certs, NSString *teamID) {
  MOLCertificate *leafCert = [certs firstObject];

  if ([leafCert.commonName isEqualToString:@"Apple Mac OS Application Signing"]) {
    return [NSString stringWithFormat:@"App Store (Team ID: %@)", teamID];
  } else if ([leafCert.commonName hasPrefix:@"Developer ID Application"]) {
    // Developer ID Application certs have the company name in the OrgName field
    // but also include it in the CommonName and we don't want to print it twice.
    return [NSString stringWithFormat:@"%@ (%@)", leafCert.orgName, teamID];
  } else if (leafCert.commonName && leafCert.orgName) {
    return [NSString stringWithFormat:@"%@ - %@", leafCert.orgName, leafCert.commonName];
  } else if (leafCert.commonName) {
    return leafCert.commonName;
  } else {
    return nil;
  }
}

NSArray<id> *CertificateChain(NSArray<MOLCertificate *> *certs) {
  NSMutableArray *certArray = [NSMutableArray arrayWithCapacity:certs.count];
  for (MOLCertificate *cert in certs) {
    [certArray addObject:(id)cert.certRef];
  }

  return certArray;
}

BOOL IsDevelopmentCert(MOLCertificate *cert) {
  // Development OID values defined by Apple and used by the Security Framework
  // https://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.31.pdf
  static NSArray *const keys = @[ @"1.2.840.113635.100.6.1.2", @"1.2.840.113635.100.6.1.12" ];

  if (!cert || !cert.certRef) {
    return NO;
  }

  NSDictionary *vals =
      CFBridgingRelease(SecCertificateCopyValues(cert.certRef, (__bridge CFArrayRef)keys, NULL));

  return vals.count > 0;
}

SNTSigningStatus SigningStatus(MOLCodesignChecker *csc, NSError *error) {
  if (error) {
    if (error.code == errSecCSUnsigned) {
      return SNTSigningStatusUnsigned;
    }
    return SNTSigningStatusInvalid;
  }
  if (csc.signatureFlags & kSecCodeSignatureAdhoc) {
    return SNTSigningStatusAdhoc;
  } else if (IsDevelopmentCert(csc.leafCertificate)) {
    return SNTSigningStatusDevelopment;
  }
  return SNTSigningStatusProduction;
}
