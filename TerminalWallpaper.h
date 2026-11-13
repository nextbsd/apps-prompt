/* Wallpaper-only X11 capture for simulated transparency. GPL-2.0-or-later. */
#import <AppKit/AppKit.h>
@interface TerminalWallpaper : NSObject
{
  NSImage *_image;
  unsigned long _pixmap;
  void *_display;
}
/* Refresh the published root pixmap; never capture windows on the desktop. */
- (BOOL)refresh;
- (NSImage *)image;
@end
