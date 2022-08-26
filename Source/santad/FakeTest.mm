#include "Source/santad/Fake.h"

// #include <gtest/gtest.h>
// #include <gmock/gmock.h>
#import <OCMock/OCMock.h>
#include <memory>
#import <XCTest/XCTest.h>

// static std::shared_ptr<int> obj;

@interface FakeTest : XCTestCase
// @property std::shared_ptr<int> _pobj;
@end

@implementation FakeTest

- (void)setUp {
  // self._pobj = std::make_shared<int>();
  // printf("\n\nSET UP: uc: %ld\n", self._pobj.use_count());
  printf("\n\nSET UP\n");
}

- (void)tearDown {
  // printf("\n\nTEAR DOWN: uc: %ld\n", self._pobj.use_count());
  printf("\n\nTEAR DOWN\n");
}

- (void)testFake {
  // DerivedFake *fake;
  // id mockFake;
  auto obj = std::make_shared<MyInt>();
  // obj = std::make_shared<int>();
  printf("Test fake: uc: %ld\n", obj.use_count());
  // DerivedFake *fake = [[DerivedFake alloc] initWithObj:obj];
  DerivedFake *fake = [[DerivedFake alloc] initWithObj:obj];
  printf("After derived init in test: uc: %ld\n", obj.use_count());

  // printf("Test fake: uc: %ld\n", self._pobj.use_count());
  // DerivedFake *fake = [[DerivedFake alloc] initWithObj:self._pobj];

  id mockFake = OCMPartialMock(fake);
  printf("After partial mock in test: uc: %ld\n", obj.use_count());
  // (void)mockFake;

  [fake doAThing];
  printf("After doAThing in test: uc: %ld\n", obj.use_count());

  [mockFake stopMocking];

  printf("\n\nexiting test...: %ld\n", obj.use_count());
}

@end
