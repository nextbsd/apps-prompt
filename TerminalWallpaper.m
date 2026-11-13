/* X11 background capture for simulated transparency. GPL-2.0-or-later. */
#import "TerminalWallpaper.h"

#ifdef TERMINAL_X11_RESIZE
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#ifdef TERMINAL_X11_COMPOSITE
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/Xrender.h>
#endif

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
  RELEASE (_backdrop);
  RELEASE (_image);
#ifdef TERMINAL_X11_RESIZE
  if (_display) XCloseDisplay ((Display *)_display);
#endif
  DEALLOC;
}

- (NSImage *)image { return _backdrop ? _backdrop : _image; }

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
  DESTROY (_image);
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
  RELEASE (bitmap);
  XDestroyImage (capture);
  return YES;
#else
  return NO;
#endif
}

- (BOOL)refreshForWindow:(unsigned long)window
{
  BOOL changed = [self refresh];
#ifdef TERMINAL_X11_COMPOSITE
  Display *display = (Display *)_display;
  if (!display || !window) return changed;
  Window root = DefaultRootWindow (display);
  int event, error, major = 0, minor = 2;
  if (!XCompositeQueryExtension (display, &event, &error)
      || !XCompositeQueryVersion (display, &major, &minor)
      || (major == 0 && minor < 2)
      || !XRenderQueryExtension (display, &event, &error)) return changed;
  XSync (display, False);
  int (*previousHandler)(Display *, XErrorEvent *) =
      XSetErrorHandler (wallpaperErrorHandler);
  wallpaperError = 0;
  if (!_redirected)
    {
      /* Automatic redirection preserves normal desktop presentation, including
       * when no compositor is running. Closing our connection releases it. */
      XCompositeRedirectSubwindows (display, root, CompositeRedirectAutomatic);
      XSync (display, False);
      _redirected = !wallpaperError;
    }
  Window parent, treeRoot, *children = NULL, frame = window;
  unsigned int count = 0;
  BOOL found = NO;
  while (!wallpaperError && XQueryTree (display, frame, &treeRoot, &parent,
                                       &children, &count))
    {
      if (children) XFree (children);
      children = NULL;
      if (parent == root) { found = YES; break; }
      if (!parent || frame == root) break;
      frame = parent;
    }
  XWindowAttributes rootAttributes;
  Pixmap canvas = None;
  Picture destination = None;
  XImage *capture = NULL;
  if (_redirected && found && !wallpaperError
      && XGetWindowAttributes (display, root, &rootAttributes)
      && (unsigned long)rootAttributes.width * rootAttributes.height <= 33554432UL
      && XQueryTree (display, root, &treeRoot, &parent, &children, &count))
    {
      XRenderPictFormat *argb = XRenderFindStandardFormat (display, PictStandardARGB32);
      canvas = XCreatePixmap (display, root, rootAttributes.width,
                              rootAttributes.height, 32);
      destination = XRenderCreatePicture (display, canvas, argb, 0, NULL);
      XRenderColor clear = {0, 0, 0, 0};
      XRenderFillRectangle (display, PictOpSrc, destination, &clear, 0, 0,
                            rootAttributes.width, rootAttributes.height);
      if (_pixmap)
        {
          XRenderPictureAttributes attributes;
          attributes.repeat = True;
          Picture wallpaper = XRenderCreatePicture (display, _pixmap,
              XRenderFindVisualFormat (display, DefaultVisual (display,
                  DefaultScreen (display))), CPRepeat, &attributes);
          XRenderComposite (display, PictOpSrc, wallpaper, None, destination,
              0, 0, 0, 0, 0, 0, rootAttributes.width, rootAttributes.height);
          XRenderFreePicture (display, wallpaper);
        }
      /* XQueryTree orders children from bottom to top. Stop at our WM frame,
       * excluding both our own pixels and every window above us. */
      for (unsigned int i = 0; i < count && children[i] != frame; i++)
        {
          XWindowAttributes attributes;
          if (!XGetWindowAttributes (display, children[i], &attributes)
              || attributes.map_state != IsViewable || attributes.class == InputOnly)
            continue;
          XRenderPictFormat *format = XRenderFindVisualFormat (display, attributes.visual);
          if (!format) continue;
          Pixmap pixels = XCompositeNameWindowPixmap (display, children[i]);
          Picture source = XRenderCreatePicture (display, pixels, format, 0, NULL);
          XRenderComposite (display, PictOpOver, source, None, destination,
              0, 0, 0, 0, attributes.x, attributes.y,
              attributes.width + 2 * attributes.border_width,
              attributes.height + 2 * attributes.border_width);
          XRenderFreePicture (display, source);
          XFreePixmap (display, pixels);
        }
      XSync (display, False);
      if (!wallpaperError)
        capture = XGetImage (display, canvas, 0, 0, rootAttributes.width,
                             rootAttributes.height, AllPlanes, ZPixmap);
    }
  if (children) XFree (children);
  if (destination) XRenderFreePicture (display, destination);
  if (canvas) XFreePixmap (display, canvas);
  XSync (display, False);
  XSetErrorHandler (previousHandler);
  DESTROY (_backdrop);
  if (capture && !wallpaperError)
    {
      NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
          initWithBitmapDataPlanes:NULL pixelsWide:capture->width pixelsHigh:capture->height
          bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
          colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:capture->width * 4 bitsPerPixel:32];
      unsigned char *bytes = [bitmap bitmapData];
      if (bytes)
        {
          for (int y = 0; y < capture->height; y++)
            for (int x = 0; x < capture->width; x++)
              {
                unsigned long pixel = XGetPixel (capture, x, y);
                unsigned int alpha = (pixel >> 24) & 255;
                unsigned char *out = bytes + y * [bitmap bytesPerRow] + x * 4;
                out[0] = alpha ? MIN (255, ((pixel >> 16) & 255) * 255 / alpha) : 0;
                out[1] = alpha ? MIN (255, ((pixel >> 8) & 255) * 255 / alpha) : 0;
                out[2] = alpha ? MIN (255, (pixel & 255) * 255 / alpha) : 0;
                out[3] = alpha;
              }
          _backdrop = [[NSImage alloc] initWithSize:NSMakeSize (capture->width, capture->height)];
          [_backdrop addRepresentation:bitmap];
        }
      RELEASE (bitmap);
    }
  if (capture) XDestroyImage (capture);
  return YES;
#else
  return changed;
#endif
}

@end
