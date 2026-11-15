/* Standalone GNUstep Prompt. GPL-2.0-or-later; see COPYING. */
#import "AppController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  AppController *controller = [AppController new];
  [NSApp setDelegate:controller];
  [NSApp run];
  [NSApp setDelegate:nil];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
