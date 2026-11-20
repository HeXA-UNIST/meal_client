#import "GeneratedPluginRegistrant.h"
#import <UIKit/UIKit.h>

// 빌드에 사용한 iOS SDK와 실행 중인 iOS가 모두 가이드를 지원해야 한다.
static inline UILayoutGuide * _Nullable BapuTopBarGuide(UIView * _Nonnull view, CGFloat height) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
  if (@available(iOS 27.1, *)) {
    UIViewLayoutRegion *region = [UIViewLayoutRegion layoutRegionForBarOnEdge:UIRectEdgeTop
                                                                       extent:height];
    return [view layoutGuideForLayoutRegion:region];
  }
#endif
  return nil;
}
