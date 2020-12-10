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

if [ -f "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" ]; then
    # macOS 10.15 or ealier.
    dmg="${OSInstaller}/Contents/SharedSupport/InstallESD.dmg"
    plist="${OSInstaller}/Contents/SharedSupport/InstallInfo.plist"
    plist_type=1015
    if [ ! -f "$plist" ]; then
        echo "Not found file: $plist"
        echo "Unknown installer type."
        exit 1
    fi
elif [ -f "${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg" ]; then
    # macOS 11.0 or later.
    dmg="${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg"
    plist="${OSInstaller}/Contents/Info.plist"
    plist_type=1100
    if [ ! -f "$plist" ]; then
        echo "Not found file: $plist"
        echo "Unknown installer type."
        exit 1
    fi
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
Parameter 4: /Applications/$( /usr/bin/basename "$OSInstaller" )
Parameter 5: $osversion
Parameter 6: (Your download trigger policy)
Parameter 7: $checksum
=====================================================

_RESULT

if [ "$plist_type" -lt 1100 ]; then
    # Build a package of installer
    if [ ! -x /usr/bin/pkgbuild ]; then exit 0; fi
    read -r -p "Would you need a package archive of $( /usr/bin/basename "$OSInstaller" )? [y/n]: " ANS
    if [ "$ANS" != y ]; then exit 0 ;fi

    echo "Ok, building package archive file of $( /usr/bin/basename "$OSInstaller" ). Wait few minutes."

    workdir="$(/usr/bin/mktemp -d)"
    PKGID="macOSUpgrade.helper-tools.pkgbuild"
    PKGFILE="${HOME}/Downloads/$( /usr/bin/basename "$OSInstaller" ).${osversion}.pkg"
    /bin/mkdir -p "$workdir/root/Applications"
    /bin/cp -a "${OSInstaller%/}" "$workdir/root/Applications"

    if [ -f "$PKGFILE" ]; then
        /bin/mv "${PKGFILE}" "${PKGFILE%.pkg}.previous.$(uuidgen).pkg"
    fi

    if /usr/bin/pkgbuild --identifier "$PKGID" --root "${workdir}/root" "$PKGFILE" > "/tmp/pkgbuid.$( /bin/date +%F_%H%M%S ).log" ; then
        echo "Done. $PKGFILE"
    else
        echo "FAILED."
    fi
else
    # https://www.jamf.com/jamf-nation/discussions/37294/package-big-sur-installer-with-composer-issue
    read -r -p "Would you need a DMG file of $( /usr/bin/basename "$OSInstaller" )? [y/n]: " ANS
    if [ "$ANS" != y ]; then exit 0 ;fi

    echo "Ok, building DMG file of $( /usr/bin/basename "$OSInstaller" ). Wait few minutes."

    workdir="$(/usr/bin/mktemp -d)"
    temp_dmg="${workdir}/osinstaller.dmg"
    dist_dmg="${HOME}/Downloads/$( /usr/bin/basename "$OSInstaller" ).${osversion}.dmg"
    sizeOfInstaller="$( /usr/bin/du -sm "$OSInstaller" | /usr/bin/awk '{print $1}' )"
    volumename="macOSInstaller"
    extra_size=512
    filesystem='APFS'

    if [ "$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print ($1 * 10 ** 2 +  $2 )}' )" -lt 1015 ]; then
        filesystem='JHFS+'
    fi

    /usr/bin/hdiutil create -size $(( sizeOfInstaller + extra_size ))m -volname "$volumename" "$temp_dmg" -fs "$filesystem" > /dev/null
    devfile="$( /usr/bin/hdiutil attach -readwrite -nobrowse "$temp_dmg" | /usr/bin/awk '$NF == "GUID_partition_scheme" {print $1}' )"

    /bin/mkdir "/Volumes/${volumename}/Applications"
    if /bin/cp -a "${OSInstaller%/}" "/Volumes/${volumename}/Applications" ; then
        /usr/bin/hdiutil detach "$devfile" > /dev/null
    else
        echo "=== DEBUG ==="
        /bin/df -lH
        echo "temp_dmg: $temp_dmg"
        exit 1
    fi

    if [ -f "$dist_dmg" ]; then
        /bin/mv "${dist_dmg}" "${dist_dmg%.dmg}.previous.$(uuidgen).dmg"
    fi

    /usr/bin/hdiutil convert "$temp_dmg" -format ULFO -o "$dist_dmg" > /dev/null

    echo "Done. $dist_dmg"
fi
/bin/rm -rf "$workdir"
