/* Wallpaper-only X11 capture for simulated transparency. GPL-2.0-or-later. */
#import "TerminalWallpaper.h"
#ifdef TERMINAL_X11_RESIZE
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
/* Xlib's error handler is process-wide. The main-thread capture is synchronous
 * and uses its own connection so stale wallpaper pixmaps cannot kill the app. */
static int wallpaperError;
static int wallpaperErrorHandler (Display *display, XErrorEvent *event)
{
  wallpaperError = 1;
  return 0;
}
static unsigned char component (unsigned long pixel, unsigned long mask)
{
  if (!mask) return 0;
  while (!(mask & 1)) { mask >>= 1; pixel >>= 1; }
  return (unsigned char)(((pixel & mask) * 255UL) / mask);
}
#endif
@implementation TerminalWallpaper
- (void)dealloc
{
  [_image release];
#ifdef TERMINAL_X11_RESIZE
  if (_display) XCloseDisplay ((Display *)_display);
#endif
  [super dealloc];
}
- (NSImage *)image { return _image; }
- (BOOL)refresh
{
#ifdef TERMINAL_X11_RESIZE
  if (!_display) _display = XOpenDisplay (NULL);
  if (!_display) return NO;
  Display *display = (Display *)_display;
  Window root = DefaultRootWindow (display);
  Pixmap pixmap = None;
  const char *names[] = { "_XROOTPMAP_ID", "ESETROOT_PMAP_ID" };
  for (int i = 0; i < 2 && !pixmap; i++)
    {
      Atom property = XInternAtom (display, names[i], True), type;
      int format;
      unsigned long count, remaining;
      unsigned char *data = NULL;
      if (property && XGetWindowProperty (display, root, property, 0, 1,
          False, XA_PIXMAP, &type, &format, &count, &remaining, &data) == Success
          && type == XA_PIXMAP && format == 32 && count == 1)
        pixmap = *(unsigned long *)data;
      if (data) XFree (data);
    }
  if (pixmap == _pixmap) return NO;
  [_image release]; _image = nil;
  _pixmap = 0;
  if (!pixmap) return YES;
  Window geometryRoot;
  int x, y;
  unsigned int width, height, border, depth;
  XSync (display, False);
  int (*previousHandler)(Display *, XErrorEvent *) =
      XSetErrorHandler (wallpaperErrorHandler);
  wallpaperError = 0;
  XImage *capture = NULL;
  if (XGetGeometry (display, pixmap, &geometryRoot, &x, &y, &width, &height,
                    &border, &depth) && !wallpaperError
      && width && height && (unsigned long)width * height <= 33554432UL
      && depth == (unsigned int)DefaultDepth (display, DefaultScreen (display)))
    capture = XGetImage (display, pixmap, 0, 0, width, height, AllPlanes, ZPixmap);
  XSync (display, False);
  XSetErrorHandler (previousHandler);
  if (!capture || wallpaperError)
    {
      if (capture) XDestroyImage (capture);
      return YES;
    }
  Visual *visual = DefaultVisual (display, DefaultScreen (display));
  if (visual->class != TrueColor)
    { XDestroyImage (capture); return YES; }
  /* Expand tiny tiles to keep painting a one-pixel root pixmap inexpensive. */
  unsigned int sourceWidth = width, sourceHeight = height;
  if (width < 256) width *= (256 + width - 1) / width;
  if (height < 256) height *= (256 + height - 1) / height;
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
      bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO
      colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:width * 3 bitsPerPixel:24];
  unsigned char *bytes = [bitmap bitmapData];
  if (bytes)
    {
      for (unsigned int row = 0; row < height; row++)
        for (unsigned int col = 0; col < width; col++)
          {
            unsigned long pixel = XGetPixel (capture, col % sourceWidth, row % sourceHeight);
            unsigned char *out = bytes + row * [bitmap bytesPerRow] + col * 3;
            out[0] = component (pixel, visual->red_mask);
            out[1] = component (pixel, visual->green_mask);
            out[2] = component (pixel, visual->blue_mask);
          }
      _image = [[NSImage alloc] initWithSize:NSMakeSize (width, height)];
      [_image addRepresentation:bitmap];
      _pixmap = pixmap;
    }
  [bitmap release];
  XDestroyImage (capture);
  return YES;
#else
  return NO;
#endif
}
@end
