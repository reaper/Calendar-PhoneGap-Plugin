# Property of Four Js*
# (c) Copyright Four Js 2017, 2017. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these
# samples are accurate and suitable for your purposes. Their inclusion is
# purely for information purposes only.

# calling make without parameters simply creates an GMI executable for the simulator
# use "make gmi.install" to install on the simulator or device depending on the TARGET

BUNDLE_IDENTIFIER   = com.4js.cdvcalendar
APPNAME             = CDVCalendar
TARGET              = simulator
TARGET              = phone
MODE                = debug
BUILD_FGL           = yes
FGLLDPATH           = ../../lib
IDENTITY='(59W7RY75ZU)'
PROVISIONING_PROFILE=/Users/leo/Library/MobileDevice/Provisioning\ Profiles/4js_wildcard

USER_EXTENSION_LIBS = $(GMIDIR)/lib/cordova/CDVCalendar.a

#include the generic Makefile-gmi with a lot of targets
ifndef GMIDIR
GMIDIR=$(FGLDIR)
endif
MAKEFILE_GMI=$(shell GMIDIR="$(GMIDIR)";echo $${GMIDIR// /\\ })/lib/Makefile-gmi
include $(MAKEFILE_GMI)

main.42m: calendars.42f events.42f newevent.42f

clean::
	rm -f *.sch *.dbs *.42*
