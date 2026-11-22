ifeq ($(GNUSTEP_MAKEFILES),)
GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make
APP_NAME = Terminal
VERSION = 1.0
Terminal_OBJC_FILES = main.m AppController.m TerminalView.m TerminalPreferences.m TerminalWallpaper.m Terminal/TerminalParser_VT100.m
Terminal_CFLAGS = -std=c99
# X11 supplies mouse state while the window manager owns the resize drag.
ifneq ($(shell pkg-config --exists x11 && echo yes),)
Terminal_OBJCFLAGS += -DTERMINAL_X11_RESIZE $(shell pkg-config --cflags x11)
Terminal_GUI_LIBS += $(shell pkg-config --libs x11)
endif
# Composite retains obscured window pixels for background sampling.
ifneq ($(shell pkg-config --exists xcomposite xrender && echo yes),)
Terminal_OBJCFLAGS += -DTERMINAL_X11_COMPOSITE $(shell pkg-config --cflags xcomposite xrender)
Terminal_GUI_LIBS += $(shell pkg-config --libs xcomposite xrender)
endif
Terminal_APPLICATION_ICON = Terminal.png
Terminal_RESOURCE_FILES = Resources/Terminal.png Resources/Help.txt COPYING COPYING.engine
include $(GNUSTEP_MAKEFILES)/application.make
check:: all
	$(MAKE) -C Tests check
