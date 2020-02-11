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

if [ ! -f  "${OSInstaller}/Contents/SharedSupport/InstallInfo.plist" ]; then
    echo "Not found ${OSInstaller}/Contents/SharedSupport/InstallInfo.plist"
    echo "Unknown installer type. Apple may change something."
    exit 1
fi

if [ ! -f  "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" ]; then
    echo "Not found ${OSInstaller}/Contents/SharedSupport/InstallESD.dmg"
    echo "This is not expected installer type."
    exit 1
fi

osversion=$(/usr/libexec/PlistBuddy -c "print 'System Image Info:version'" "${OSInstaller}/Contents/SharedSupport/InstallInfo.plist")
echo "Wait seconds, getting checksum..."
checksum=$(/sbin/md5 -r "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" | /usr/bin/awk '{print $1}')

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
PKGFILE="${HOME}/Desktop/$(basename "$OSInstaller" ).${osversion}.pkg"
workdir="$(/usr/bin/mktemp -d)"
/bin/mkdir -p "$workdir/root/Applications"
/bin/cp -a "$OSInstaller" "$workdir/root/Applications"

if [ -f "$PKGFILE" ]; then
   /bin/mv "${PKGFILE}" "${PKGFILE%.pkg}.previous.$(uuidgen).pkg"
fi

/usr/bin/pkgbuild --identifier "$PKGID" --root "${workdir}/root" "$PKGFILE" > "/tmp/pkgbuid.$( date +%F_%H%M%S ).log"

/bin/rm -rf "$workdir"
echo "Done. $PKGFILE"
