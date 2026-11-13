/* X11 background capture for simulated transparency. GPL-2.0-or-later. */
#import <AppKit/AppKit.h>

@interface TerminalWallpaper : NSObject
{
  NSImage *_image;
  unsigned long _pixmap;
  void *_display;
  NSImage *_backdrop;
  BOOL _redirected;
}

/* Refresh the published root pixmap; never capture windows on the desktop. */
- (BOOL)refresh;
- (NSImage *)image;
/* Sample the root and windows below the supplied native X11 window. */
- (BOOL)refreshForWindow:(unsigned long)window;

@end
