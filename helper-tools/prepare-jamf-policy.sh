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
#-   Done. See ~/Downloads/Install macOS Mojave.app.10.14
#-   $
#-

function get_install_os_info(){
    local dmg_file tmpfile osversion osbuild info_file devfile

    dmg_file="$1"
    if [ ! -f "$dmg_file" ]; then
        echo "Not found: $dmg_file"
        exit 1
    fi
    tmpfile="$( /usr/bin/mktemp )"

    /usr/bin/hdiutil attach -mountrandom /Volumes -noverify -readonly -nobrowse "$dmg_file" > "$tmpfile"
    devfile="$( /usr/bin/awk '$NF == "GUID_partition_scheme" {print $1}' "$tmpfile" )"
    if [ -z "$devfile" ]; then
        echo "failed to mount: $dmg_file"
        rm -rf "$tmpfile"
        exit 1
    fi
    mountpoint="$( /usr/bin/awk '$2 == "Apple_HFS" {print $3}' "$tmpfile" )"
    if [ -z "$mountpoint" ]; then
        echo "something changed. failed to get mount point"
        rm -rf "$tmpfile"
        exit 1
    fi

    info_file="${mountpoint}/com_apple_MobileAsset_MacSoftwareUpdate/com_apple_MobileAsset_MacSoftwareUpdate.xml"
    osversion="$( /usr/libexec/PlistBuddy -c "print Assets:0:OSVersion" "$info_file" )"
    osbuild="$( /usr/libexec/PlistBuddy -c "print Assets:0:Build" "$info_file" )"

    rm -rf "$tmpfile"
    /usr/bin/hdiutil detach "$devfile" > /dev/null 2>&1
    echo "${osversion}/${osbuild}"
}

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
    plist_type=1015
    dmg="${OSInstaller}/Contents/SharedSupport/InstallESD.dmg"
    plist="${OSInstaller}/Contents/SharedSupport/InstallInfo.plist"
    if [ ! -f "$plist" ]; then
        echo "Not found file: $plist"
        echo "Unknown installer type."
        exit 1
    fi
    osversion="$(/usr/libexec/PlistBuddy -c "print 'System Image Info:version'" "$plist")"
    output_dir="${HOME}/Downloads/$(basename "${OSInstaller%.app}" ).${osversion}"
    installer_archive="${output_dir}/$(basename "${OSInstaller}" ).${osversion}.pkg"
    installer_info="${output_dir}/$(basename "${OSInstaller}" ).${osversion}.txt"
    msg1="Would you need a package archive of $( basename "$OSInstaller" )?"
    msg2="Ok, building package archive file of $( basename "$OSInstaller"). Wait few minutes."
elif [ -f "${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg" ]; then
    # macOS 11.0 or later.
    plist_type=1100
    dmg="${OSInstaller}/Contents/SharedSupport/SharedSupport.dmg"
    if [ ! -f "$dmg" ]; then
        echo "Not found file: $plist"
        echo "Unknown installer type."
        exit 1
    fi
    osinfo="$(get_install_os_info "$dmg")"
    osversion="$(/usr/bin/dirname "$osinfo")"
    osbuild="$(/usr/bin/basename "$osinfo")"
    output_dir="${HOME}/Downloads/$(basename "${OSInstaller%.app}" ).${osversion}-${osbuild}"
    installer_archive="${output_dir}/$(basename "${OSInstaller}" ).${osversion}-${osbuild}.dmg"
    installer_info="${output_dir}/$(basename "${OSInstaller}" ).${osversion}-${osbuild}.txt"
    msg1="Would you need a dmg archive of $( basename "$OSInstaller" )?"
    msg2="Ok, creating dmg archive file of $( basename "$OSInstaller"). Wait few minutes."
else
    echo "Not found dmg file."
    echo "This is not expected installer type."
    exit 1
fi

echo "Wait minutes, getting checksum..."
checksum=$(/sbin/md5 -r "$dmg" | /usr/bin/awk '{print $1}')

result_file="$( /usr/bin/mktemp )"
/bin/cat <<_RESULT | /usr/bin/tee "$result_file"

=====================================================
Parameters for JamfPro policy:
Parameter 4: /Applications/$( /usr/bin/basename "$OSInstaller" )
Parameter 5: $osversion
Parameter 6: (Your download trigger policy)
Parameter 7: $checksum
=====================================================
_RESULT

if [ "$plist_type" -lt 1100 ] && [ ! -x /usr/bin/pkgbuild ]; then
    /bin/rm -f "$result_file"
    exit 0
fi

read -r -p "$msg1 [y/n]: " ANS
if [ "$ANS" != y ]; then rm -f  "$result_file"; exit 0; fi
echo "$msg2"

uuid="$( /usr/bin/uuidgen )"
workdir="$(/usr/bin/mktemp -d)"
/bin/mkdir -p "$output_dir"

if [ -f "$installer_info" ]; then
    /bin/mv "$installer_info" "${installer_info%.txt}.previous.$(uuid).txt"
fi
/bin/mv "$result_file" "$installer_info"

if [ "$plist_type" -lt 1100 ]; then
    # Build a package of installer
    PKGID="macOSUpgrade.helper-tools.pkgbuild"
    /bin/mkdir -p "$workdir/root/Applications"
    /bin/cp -a "${OSInstaller%/}" "$workdir/root/Applications"

    if [ -f "$installer_archive" ]; then
        /bin/mv "${installer_archive}" "${installer_archive%.pkg}.previous.${uuid}.pkg"
    fi

    if ! /usr/bin/pkgbuild --identifier "$PKGID" --root "${workdir}/root" "$installer_archive" > "/tmp/pkgbuid.$( /bin/date +%F_%H%M%S ).log" 2>&1 ; then
        echo "FAILED. (See /tmp/pkgbuid.$( /bin/date +%F_%H%M%S ).log"
    fi
else
    # https://www.jamf.com/jamf-nation/discussions/37294/package-big-sur-installer-with-composer-issue
    temp_dmg="${workdir}/osinstaller.dmg"
    sizeOfInstaller="$( /usr/bin/du -sm "$OSInstaller" | /usr/bin/awk '{print $1}' )"
    volumename="macOSInstaller"
    extra_size=512
    filesystem='APFS'

    if [ "$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print ($1 * 10 ** 2 +  $2 )}' )" -lt 1015 ]; then
        extra_size=512
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

    if [ -f "$installer_archive" ]; then
        /bin/mv "${installer_archive}" "${installer_archive%.pkg}.previous.${uuid}.dmg"
    fi

    /usr/bin/hdiutil convert "$temp_dmg" -format ULFO -o "$installer_archive" > /dev/null
fi

/bin/rm -rf "$workdir"
echo "Done. See $output_dir"
