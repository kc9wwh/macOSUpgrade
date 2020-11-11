#!/bin/bash
#-
#- Usage
#-   $ ./prepare-jamf-policy.sh "/path/to/Install macOS.app"
#-   Wait seconds, getting checksum...
#-
#-   =====================================================
#-   Upgrade macOS Parameters:
#-   Parameter 4: /Applications/Install macOS.app
#-   Parameter 5: 10.14
#-   Parameter 6: (Your download trigger policy)
#-   Parameter 7: 20acadc8d66bb3d882bc0fedf1358c64
#-   =====================================================
#-
#-   Would you need a package archive of Install macOS Mojave.app? [y/n]: y
#-   Ok, building package archive file of Install macOS Mojave.app. Wait few minutes.
#-   Done. ~/Desktop/Install macOS Mojave.app.10.14.pkg
#-   $
#-

if [ $# -eq 0 ]; then
    # Show help
    /usr/bin/grep ^#- "$0" | cut -c 4-
    exit 0
fi

OSInstaller="$1"
if [ ! -d "$OSInstaller" ]; then
    echo "Not found $OSInstaller !"
    exit 1
fi

if [ ! -d  "${OSInstaller}/Contents/SharedSupport" ]; then
    echo "This installer looks like kind of 'stub' installer."
    /usr/bin/du -sh "${OSInstaller}"
    echo "Use full size intaller."
    exit 1
fi

if [ -f "${OSInstaller}/Contents/SharedSupport/InstallInfo.plist" ]; then
    # macOS 10.15 or ealier.
    plist_type=1015
    plist="${OSInstaller}/Contents/SharedSupport/InstallInfo.plist"
elif [ -f "${OSInstaller}/Contents/Info.plist" ]; then
    # macOS 11.0 or later.
    plist_type=1100
    plist="${OSInstaller}/Contents/Info.plist"
else
    echo "Not found plist file."
    echo "Unknown installer type. Apple may change something."
    exit 1
fi

if [ -f "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" ]; then
    # macOS 10.15 or ealier.
    dmg="${OSInstaller}/Contents/SharedSupport/InstallESD.dmg"
elif [ -f "${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg" ]; then
    # macOS 11.0 or later.
    dmg="${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg"
else
    echo "Not found dmg file."
    echo "This is not expected installer type."
    exit 1
fi

if [ "$plist_type" -lt 1100 ]; then
    osversion=$(/usr/libexec/PlistBuddy -c "print 'System Image Info:version'" "$plist")
else
    osversion=$(/usr/libexec/PlistBuddy -c "print DTPlatformVersion" "$plist")
fi
echo "Wait seconds, getting checksum..."
checksum=$(/sbin/md5 -r "$dmg" | /usr/bin/awk '{print $1}')

cat <<_RESULT

=====================================================
Parameters for JamfPro policy:
Parameter 4: /Applications/$( basename "$OSInstaller" )
Parameter 5: $osversion
Parameter 6: (Your download trigger policy)
Parameter 7: $checksum
=====================================================

_RESULT

# Build a package of installer
if [ ! -x /usr/bin/pkgbuild ]; then exit 0; fi
read -r -p "Would you need a package archive of $( basename "$OSInstaller" )? [y/n]: " ANS
if [ "$ANS" != y ]; then exit 0 ;fi
echo "Ok, building package archive file of $( basename "$OSInstaller"). Wait few minutes."

PKGID="macOSUpgrade.helper-tools.pkgbuild"
PKGFILE="${HOME}/Downloads/$(basename "$OSInstaller" ).${osversion}.pkg"
workdir="$(/usr/bin/mktemp -d)"
/bin/mkdir -p "$workdir/root/Applications"
/bin/cp -a "${OSInstaller%/}" "$workdir/root/Applications"

if [ -f "$PKGFILE" ]; then
   /bin/mv "${PKGFILE}" "${PKGFILE%.pkg}.previous.$(uuidgen).pkg"
fi

/usr/bin/pkgbuild --identifier "$PKGID" --root "${workdir}/root" "$PKGFILE" > "/tmp/pkgbuid.$( date +%F_%H%M%S ).log"

/bin/rm -rf "$workdir"
echo "Done. $PKGFILE"
