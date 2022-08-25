#include "Source/santad/Fake.h"

#include <map>

@implementation BaseFake {
  std::shared_ptr<int> _obj;
}

- (instancetype)initWithObj:(std::shared_ptr<int>)obj {
  self = [super init];
  if (self) {
    _obj = std::move(obj);
  }
  return self;
}

@end

@implementation DerivedFake {
  std::map<int, int> unused;
}

- (instancetype)initWithObj:(std::shared_ptr<int>)obj {
  return [super initWithObj:std::move(obj)];
}

- (void)doAThing {
  printf("\nDo A Thing!\n");
}

@end
