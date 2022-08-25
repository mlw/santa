#include "Source/santad/Fake.h"

// #include <gtest/gtest.h>
// #include <gmock/gmock.h>
#import <OCMock/OCMock.h>
#include <memory>
#import <XCTest/XCTest.h>

@interface FakeTest : XCTestCase
@end

@implementation FakeTest

- (void)setUp {
  printf("\n\nSET UP\n");
}

- (void)tearDown {
  printf("\n\nTEAR DOWN\n");
}

- (void)testFake {
  auto obj = std::make_shared<int>();

  DerivedFake *fake = [[DerivedFake alloc] initWithObj:obj];

  id mockFake = OCMPartialMock(fake);

  [mockFake doAThing];

  [mockFake stopMocking];
}

@end
