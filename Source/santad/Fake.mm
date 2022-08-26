#include "Source/santad/Fake.h"

#include <map>

int xyz = 100;
class FooClass {
public:
  // FooClass() { printf("\n\nfc ctor\n\n"); }
  ~FooClass() { printf("\n\nfc dtor\n\n"); }
  //~FooClass() = default;
};

@interface BaseFake()
// @property std::shared_ptr<MyInt> obj;
@end
@implementation BaseFake {
  // std::shared_ptr<int> _obj;
  std::shared_ptr<MyInt> _obj;
  MyInt baseInt;
}

- (instancetype)initWithObj:(std::shared_ptr<MyInt>)obj {
  self = [super init];
  if (self) {
    _obj = std::move(obj);
    printf("Base init: obj uc: %ld, | _obj uc: %ld\n",
        obj.use_count(), _obj.use_count());
  }
  return self;
}

- (void)printUseCount:(const char*)s {
  printf("%s: use count: %ld\n", s, _obj.use_count());
}

- (void)dealloc {
  printf("\n\n BASE DEALLOC: uc: %ld\n", _obj.use_count());
}

@end

@interface DerivedFake()
// @property std::map<int, int> unused;
@end
@implementation DerivedFake {
  // std::map<int, int> unused;
  // MyInt derivedInt;
  // FooClass fc;
  NSString *unused;
  // void *unused;
}

- (instancetype)initWithObj:(std::shared_ptr<MyInt>)obj {
  printf("Derived init: uc: %ld\n", obj.use_count());
  return [super initWithObj:std::move(obj)];
}

- (void) dealloc {
  [self printUseCount:"DERIVED DEALLOC"];
  // printf("\n\n DERIVED DEALLOC: uc: %ld\n", _obj.use_count());
}

- (void)doAThing {
  [self printUseCount:"doAThing"];
  // printf("\nDo A Thing! uc: %ld\n", self.obj.use_count());
}

@end
