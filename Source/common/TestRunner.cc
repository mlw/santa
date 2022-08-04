// #include <gtest/gtest>
#include "gtest/gtest.h"
#include <stdio.h>

// #define IDENT(x) x
// #define XSTR(x) #x
// #define STR(x) XSTR(x)
// #define PATH(x,y) STR(IDENT(x)IDENT(y))

// #define SANTA_TEST_HEADER_DIR Source/common
// #define SANTA_TEST_HEADER_File TestTest.h

// #include PATH(Dir,File)
// #include PATH(SANTA_TEST_HEADER_DIR,SANTA_TEST_HEADER_FILE)

// #include "Source/common/TestTest.h"

// TEST(TestTestMain, SubTwoMain) {
//   printf("asdgf\n");
//   EXPECT_EQ(5, 5);
// }

int main(int argc, char* argv[]) {
  ::testing::InitGoogleTest(&argc, argv);
  printf("running tests...........\n");
  int x = RUN_ALL_TESTS();
  printf("done running tests......\n");
  return x;
}
