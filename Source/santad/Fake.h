#import <Foundation/Foundation.h>

#include <memory>

@interface BaseFake : NSObject
- (instancetype)initWithObj:(std::shared_ptr<int>)obj;
@end

@interface DerivedFake : BaseFake
- (instancetype)initWithObj:(std::shared_ptr<int>)obj;
- (void)doAThing;
@end
