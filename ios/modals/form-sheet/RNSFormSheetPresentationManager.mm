#import "RNSFormSheetPresentationManager.h"
#import "RNSFormSheetContentController.h"
#import "RNSFormSheetPresentationState.h"
#import "RNSPresentationSourceProvider.h"

#import <React/RCTLog.h>

@implementation RNSFormSheetPresentationManager {
  RNSFormSheetPresentationState _state;
  BOOL _waitingForTransition;
  BOOL _retriedRefusedWait;
}

- (instancetype)init
{
  if (self = [super init]) {
    _state = RNSFormSheetPresentationStateDismissed;
  }
  return self;
}

- (void)updatePresentationIfNeededWithProvider:(id<RNSFormSheetPresentationProvider>)provider
                                    controller:(RNSFormSheetContentController *)controller
{
  if (_waitingForTransition) {
    return;
  }

  BOOL shouldBeOpen = provider.isOpen;

  if (shouldBeOpen) {
    [self presentIfNeededWithProvider:provider controller:controller];
  } else {
    [self dismissIfNeededWithProvider:provider controller:controller];
  }
}

- (void)presentIfNeededWithProvider:(id<RNSFormSheetPresentationProvider>)provider
                         controller:(RNSFormSheetContentController *)controller
{
  if (_state != RNSFormSheetPresentationStateDismissed) {
    _retriedRefusedWait = NO;
    return;
  }

  UIWindow *window = provider.hostWindow;
  if (window == nil) {
    _retriedRefusedWait = NO;
    return;
  }

  UIViewController *presentationSourceViewController =
      [RNSPresentationSourceProvider findViewControllerForPresentationInWindow:window];
  if (presentationSourceViewController == nil) {
    RCTLogError(
        @"[RNScreens] Failed to present form sheet: The source view controller cannot be found for target window.");
    _retriedRefusedWait = NO;
    return;
  }

  if ([self waitForTransitionOf:presentationSourceViewController provider:provider controller:controller]) {
    return;
  }

  _state = RNSFormSheetPresentationStatePresenting;
  [controller prepareForPresentation];

  __weak auto weakSelf = self;
  [presentationSourceViewController presentViewController:controller
                                                 animated:YES
                                               completion:^{
                                                 auto strongSelf = weakSelf;
                                                 if (!strongSelf) {
                                                   return;
                                                 }

                                                 strongSelf->_state = RNSFormSheetPresentationStatePresented;
                                                 [strongSelf updatePresentationIfNeededWithProvider:provider
                                                                                         controller:controller];
                                               }];
}

- (void)dismissIfNeededWithProvider:(id<RNSFormSheetPresentationProvider>)provider
                         controller:(RNSFormSheetContentController *)controller
{
  if (_state != RNSFormSheetPresentationStatePresented) {
    _retriedRefusedWait = NO;
    return;
  }

  UIViewController *presentingViewController = controller.presentingViewController;
  if (presentingViewController == nil) {
    _state = RNSFormSheetPresentationStateDismissed;
    _retriedRefusedWait = NO;
    return;
  }

  if ([self waitForTransitionOf:controller provider:provider controller:controller]) {
    return;
  }

  _state = RNSFormSheetPresentationStateDismissing;

  __weak auto weakSelf = self;
  [presentingViewController dismissViewControllerAnimated:YES
                                               completion:^{
                                                 auto strongSelf = weakSelf;
                                                 if (!strongSelf) {
                                                   return;
                                                 }

                                                 strongSelf->_state = RNSFormSheetPresentationStateDismissed;
                                                 [strongSelf updatePresentationIfNeededWithProvider:provider
                                                                                         controller:controller];

                                                 [controller.delegate sheetControllerDidDismiss:controller];
                                               }];
}

// UIKit drops a presentation or dismissal asked of a controller that is still appearing or disappearing,
// such as one being swiped away, without calling its completion; ask again once that transition ends.
- (BOOL)waitForTransitionOf:(UIViewController *)viewController
                   provider:(id<RNSFormSheetPresentationProvider>)provider
                 controller:(RNSFormSheetContentController *)controller
{
  id<UIViewControllerTransitionCoordinator> coordinator = viewController.transitionCoordinator;
  if (coordinator == nil) {
    _retriedRefusedWait = NO;
    return NO;
  }

  _waitingForTransition = YES;
  __weak auto weakSelf = self;
  dispatch_block_t resume = ^{
    auto strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf->_waitingForTransition = NO;
    [strongSelf updatePresentationIfNeededWithProvider:provider controller:controller];
  };
  // A coordinator that refuses the block never calls its completion either.
  BOOL queued = [coordinator animateAlongsideTransition:nil
                                             completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                                               dispatch_async(dispatch_get_main_queue(), resume);
                                             }];
  if (queued) {
    _retriedRefusedWait = NO;
  } else if (!_retriedRefusedWait) {
    _retriedRefusedWait = YES;
    dispatch_async(dispatch_get_main_queue(), resume);
  } else {
    // The coordinator refuses until its transition ends, and that transition needs the main queue meanwhile.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC), dispatch_get_main_queue(), resume);
  }
  return YES;
}

- (BOOL)handleNativeDismiss
{
  if (_state == RNSFormSheetPresentationStateDismissing || _state == RNSFormSheetPresentationStateDismissed) {
    return NO;
  }

  _state = RNSFormSheetPresentationStateDismissed;
  return YES;
}

@end
