// #include <gtest/gtest.h>
#include "gtest/gtest.h"

#include "Source/santad/EventProviders/EndpointSecurity/EndpointSecurityAPI.h"
#include "Source/santad/EventProviders/AuthResultCache.h"

using santa::santad::event_providers::AuthResultCache;
using santa::santad::event_providers::endpoint_security::EndpointSecurityAPI;

TEST(TestTestTestASDF, SubTwoNumsNoHdr) {
  // printf("TestTestTestASDF | SubTwoNums | ENTER\n");
  EXPECT_EQ(5, 7 - 2);
}

TEST(TestTestTestASDF, AddTwoNumsNoHdr) {
  // printf("TestTestTestASDF | AddTwoNums | ENTER\n");
  EXPECT_EQ(5, 2 + 3);
}

// void doObjCppSubTwoNums() {
//   auto esapi = std::make_shared<EndpointSecurityAPI>();
//   auto cache = std::make_shared<AuthResultCache>(esapi);
//   EXPECT_EQ(5, 7 - 2);
// }

// void doObjCppAddTwoNums() {
//   EXPECT_EQ(5, 2 + 3);
// }
