#!/usr/bin/env python

import plistlib
import os.path

installInfo = "/Applications/Install macOS Sierra.app/Contents/SharedSupport/InstallInfo.plist"

present = os.path.isfile(installInfo)
if present == True:
    plist = plistlib.readPlist(installInfo)
    version = plist["System Image Info"]["version"]
    print '<result>%s</result>' % version
else:
    print '<result>Installer Not Present</result>'