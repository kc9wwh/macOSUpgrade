#!/bin/bash
#-
#- Usage
#-   $ gather-installer-info.sh "/Applications/Install macOS.app"
#-   Wait seconds, getting checksumm...
#-
#-   =====================================================
#-   Upgrade macOS Parameters:
#-   Parameter 4: /Applications/Install macOS.app
#-   Parameter 5: 10.14
#-   Parameter 6: (Your download trigger policy)
#-   Parameter 7: 20acadc8d66bb3d882bc0fedf1358c64
#-   =====================================================
#-
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

if [ ! -f  "${OSInstaller}/Contents/SharedSupport/InstallInfo.plist" ]; then
    echo "Not found ${OSInstaller}/Contents/SharedSupport/InstallInfo.plist"
    echo "Unknown installer type. Apple may change something."
    exit 1
fi

if [ ! -f  "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" ]; then
    echo "Not found ${OSInstaller}/Contents/SharedSupport/InstallESD.dmg"
    echo "Thi is not expected installer type."
    exit 1
fi

osversion=$(/usr/libexec/PlistBuddy -c "print 'System Image Info:version'" "${OSInstaller}/Contents/SharedSupport/InstallInfo.plist")
echo "Wait seconds, getting checksumm..."
checksum=$(/sbin/md5 -r "${OSInstaller}/Contents/SharedSupport/InstallESD.dmg" | /usr/bin/awk '{print $1}')

cat <<_RESULT

=====================================================
Parameters for JamfPro policy:
Parameter 4: $OSInstaller
Parameter 5: $osversion
Parameter 6: (Your download trigger policy)
Parameter 7: $checksum
=====================================================

_RESULT
