#import <Foundation/Foundation.h>

#include <memory>

extern int xyz;
class MyInt {
public:
  MyInt() //{
    : mine_(xyz++) {
    // printf("\n\nMyInt CTOR\n");
    printf("\n\nMyInt CTOR: %d\n", mine_);
  }
  ~MyInt() {
    // printf("\n\nMyInt DTOR\n");
    printf("\n\nMyInt DTOR: %d\n", mine_);
  }

  int mine_;
};

@interface BaseFake : NSObject
- (instancetype)initWithObj:(std::shared_ptr<MyInt>)obj;
@end

@interface DerivedFake : BaseFake
- (instancetype)initWithObj:(std::shared_ptr<MyInt>)obj;
- (void)doAThing;
@end
