#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Copyright (c) 2019 Jamf.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the Jamf nor the names of its contributors may be
#                 used to endorse or promote products derived from this software without
#                 specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This script was designed to be used in a Self Service policy to ensure specific
# requirements have been met before proceeding with an in-place upgrade of the macOS,
# as well as to address changes Apple has made to the ability to complete macOS upgrades
# silently.
#
# REQUIREMENTS:
#           - Jamf Pro
#           - macOS Clients running version 10.10.5 or later
#           - macOS Installer 10.12.4 or later
#           - eraseInstall option is ONLY supported with macOS Installer 10.13.4+ and client-side macOS 10.13+
#           - Look over the USER VARIABLES and configure as needed.
#           - To use the re-enroll functions look at https://github.com/cubandave/re-enroll-mac-into-jamf-after-wipe
#
# For more information, visit https://github.com/kc9wwh/macOSUpgrade
#
# Written by: Joshua Roskos | Jamf
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# USER VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##This is the custom event name used to create the install package for automatically enrolling 
##You can statically set this a policy by setting it here
##You can also make this dynamic to enroll the computer into different Jamf Pro environments
##For more information please see the project
##https://github.com/cubandave/re-enroll-mac-into-jamf-after-wipe
autoPKGEnrollmentEventName="${11}"
if [[ -z "$autoPKGEnrollmentEventName" ]] ;then
    ##add your own event name here if you want this to be static
    autoPKGEnrollmentEventName=""
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# STATIC VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

jamfBinary="/usr/local/jamf/bin/jamf"
jHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# POLICY VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Specify path to OS installer. Use Parameter 4 in the JSS, or specify here
##Example: /Applications/Install macOS High Sierra.app
OSInstaller="$4"

##Version of Installer OS. Use Parameter 5 in the JSS, or specify here.
##Example Command: /usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallInfo.plist"
##Example: 10.12.5
version="$5"
versionMajor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $2}' )
versionMinor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $3}' )

##Custom Trigger used for download. Use Parameter 6 in the JSS, or specify here.
##This should match a custom trigger for a policy that contains just the
##MacOS installer. Make sure that the policy is scoped properly
##to relevant computers and/or users, or else the custom trigger will
##not be picked up. Use a separate policy for the script itself.
##Example trigger name: download-sierra-install
download_trigger="$6"

##MD5 Checksum of InstallESD.dmg
##This variable is OPTIONAL
##Leave the variable BLANK if you do NOT want to verify the checksum (DEFAULT)
##Example Command: /sbin/md5 /Applications/Install\ macOS\ High\ Sierra.app/Contents/SharedSupport/InstallESD.dmg
##Example MD5 Checksum: b15b9db3a90f9ae8a9df0f81741efa2b
installESDChecksum="$7"

##Valid Checksum?  O (Default) for false, 1 for true.
validChecksum=0

##Unsuccessful Download?  0 (Default) for false, 1 for true.
unsuccessfulDownload=0

##Erase & Install macOS (Factory Defaults)
##Requires macOS Installer 10.13.4 or later
##Disabled by default
##Options: 0 = Disabled / 1 = Enabled
##Use Parameter 8 in the JSS.
eraseInstall="$8"
if [ "$eraseInstall" != "1" ]; then eraseInstall=0 ; fi
#macOS Installer 10.13.3 or earlier set 0 to it.
if [ "$versionMajor${versionMinor:=0}" -lt 134 ]; then
    eraseInstall=0
fi

##Enter 0 for Full Screen, 1 for Utility window (screenshots available on GitHub)
##Full Screen by default
##Use Parameter 9 in the JSS.
userDialog="$9"
if [ "$userDialog" != "1" ]; then userDialog=0 ; fi

##Options for computer name handling for re-enroll workflows
##Use this to control the way that re-enrollment to your jamf Pro server is done
##Requires macOS Installer 10.13.4 or later
##NOTE: To Default to assigning no computer after the wipe put nothing in here
##(ask) - Use jamfHelper to ask the user what to do with the computer name 
##(keepname) - Default to automatically preserve computer name 
##(prename) - Default to automatically asking for a new computer name 
##(splashbuddy) - Add this to the parameter setting to automatically create a ComputerName.txt and .SplashBuddyFormDone 
##For more information please see the project
##https://github.com/cubandave/re-enroll-mac-into-jamf-after-wipe
##make variable lower case
reEnrollmentMethodChecks=$(echo "${10}" | tr '[:upper:]' '[:lower:]')

# Control for auth reboot execution.
if [ "$versionMajor" -ge 14 ]; then
    # Installer of macOS 10.14 or later set cancel to auth reboot.
    cancelFVAuthReboot=1
else
    # Installer of macOS 10.13 or earlier try to do auth reboot.
    cancelFVAuthReboot=0
fi

##Title of OS
macOSname=$(/bin/echo "$OSInstaller" | /usr/bin/sed -E 's/(.+)?Install(.+)\.app\/?/\2/' | /usr/bin/xargs)

##Title to be used for userDialog (only applies to Utility Window)
title="$macOSname Upgrade"

##Heading to be used for userDialog
heading="Please wait as we prepare your computer for $macOSname..."

##Title to be used for userDialog
description="This process will take approximately 5-10 minutes.
Once completed your computer will reboot and begin the upgrade."

##Description to be used prior to downloading the OS installer
dldescription="We need to download $macOSname to your computer, this will \
take several minutes."

##Jamf Helper HUD Position if macOS Installer needs to be downloaded
##Options: ul (Upper Left); ll (Lower Left); ur (Upper Right); lr (Lower Right)
##Leave this variable empty for HUD to be centered on main screen
dlPosition="ul"

##Icon to be used for userDialog
##Default is macOS Installer logo which is included in the staged installer package
icon="$OSInstaller/Contents/Resources/InstallAssistant.icns"

##First run script to remove the installers after run installer
finishOSInstallScriptFilePath="/usr/local/jamfps/finishOSInstall.sh"

##Launch deamon settings for first run script to remove the installers after run installer
osinstallersetupdDaemonSettingsFilePath="/Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist"

##Launch agent settings for filevault authenticated reboots
osinstallersetupdAgentSettingsFilePath="/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"

##Amount of time (in seconds) to allow a user to connect to AC power before moving on
##If null or 0, then the user will not have the opportunity to connect to AC power
acPowerWaitTimer="0"

##Declare the sysRequirementErrors array
declare -a sysRequirementErrors

##Icon to display during the AC Power warning
warnIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"

##Icon to display when errors are found
errorIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FUNCTIONS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

kill_process() {
    processPID="$1"
    if /bin/ps -p "$processPID" > /dev/null ; then
        /bin/kill "$processPID"
        wait "$processPID" 2>/dev/null
    fi
}

wait_for_ac_power() {
    local jamfHelperPowerPID
    jamfHelperPowerPID="$1"
    # Loop for "acPowerWaitTimer" seconds until either AC Power is detected or the timer is up
    /bin/echo "Waiting for AC power..."
    while [[ "$acPowerWaitTimer" -gt "0" ]]; do
        if /usr/bin/pmset -g ps | /usr/bin/grep "AC Power" > /dev/null ; then
            /bin/echo "Power Check: OK - AC Power Detected"
            kill_process "$jamfHelperPowerPID"
            return
        fi
        sleep 1
        ((acPowerWaitTimer--))
    done
    kill_process "$jamfHelperPowerPID"
    sysRequirementErrors+=("Is connected to AC power")
    /bin/echo "Power Check: ERROR - No AC Power Detected"
}

downloadInstaller() {
    /bin/echo "Downloading macOS Installer..."
    "$jHelper" \
        -windowType hud -windowPosition $dlPosition -title "$title" -alignHeading center -alignDescription left -description "$dldescription" \
        -lockHUD -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100 &
    ##Capture PID for Jamf Helper HUD
    jamfHUDPID=$!
    ##Run policy to cache installer
    "$jamfBinary" policy -event "$download_trigger"
    ##Kill Jamf Helper HUD post download
    kill_process "$jamfHUDPID"
}

validate_power_status() {
    ##Check if device is on battery or ac power
    ##If not, and our acPowerWaitTimer is above 1, allow user to connect to power for specified time period
    if /usr/bin/pmset -g ps | /usr/bin/grep "AC Power" > /dev/null ; then
        /bin/echo "Power Check: OK - AC Power Detected"
    else
        if [[ "$acPowerWaitTimer" -gt 0 ]]; then
            /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Waiting for AC Power Connection" -icon "$warnIcon" -description "Please connect your computer to power using an AC power adapter. This process will continue once AC power is detected." &
            wait_for_ac_power "$!"
        else
            sysRequirementErrors+=("Is connected to AC power")
            /bin/echo "Power Check: ERROR - No AC Power Detected"
        fi
    fi
}

validate_free_space() {
    ##Check if free space > 15GB (10.13) or 20GB (10.14+)
    osMajor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $2}' )
    osMinor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $3}' )
    if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
        freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Available Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
    else
        freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
    fi

    requiredDiskSpaceSizeGB=$([ "$osMajor" -ge 14 ] && /bin/echo "20" || /bin/echo "15")
    if [[ ${freeSpace%.*} -ge $(( requiredDiskSpaceSizeGB * 1000 * 1000 * 1000 )) ]]; then
        /bin/echo "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
    else
        sysRequirementErrors+=("Has at least ${requiredDiskSpaceSizeGB}GB of Free Space")
        /bin/echo "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
    fi
}

verifyChecksum() {
    if [ -n "$installESDChecksum" ]; then
        osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
        if [ "$osChecksum" = "$installESDChecksum" ]; then
            /bin/echo "Checksum: Valid"
            validChecksum=1
            return
        else
            /bin/echo "Checksum: Not Valid"
            /bin/echo "Beginning new dowload of installer"
            /bin/rm -rf "$OSInstaller"
            /bin/sleep 2
            downloadInstaller
        fi
    else
        ##Checksum not specified as script argument, assume true
        validChecksum=1
        return
    fi
}

cleanExit() {
    ##if exiting on an error killall jamfHelper Windows too
    if [[ "$1" != 0 ]] ; then /usr/bin/killall jamfHelper ; fi
    ## Remove Script
    /bin/rm -f "$finishOSInstallScriptFilePath" 2>/dev/null
    /bin/rm -f "$osinstallersetupdDaemonSettingsFilePath" 2>/dev/null
    /bin/rm -f "$osinstallersetupdAgentSettingsFilePath" 2>/dev/null
    /bin/kill "${caffeinatePID}"
    exit "$1"
}

fn_askWhatToDoForComputerName () {

    keepMessage="Do you want to KEEP the computer name after erasing? 

Current Computer Name: $currentComputerName

To rename click 'Other'.

"

    renameMessage="Do you want to RENAME the computer name after erasing? 

Current Computer Name: $currentComputerName

To not assign any name click 'No Name'.

"


    toKeepOrNotToKeep=$( "$jHelper" -windowType hud -icon "$icon" -heading "Computer Name Setting" -description "$keepMessage" -button1 "Keep" -button2 "Other" -defaultButton 1 -timeout 300 )
    if [[ "$toKeepOrNotToKeep" = 0 ]]; then
        keep=true
    elif [[ "$toKeepOrNotToKeep" = 2 ]] || [[ "$toKeepOrNotToKeep" = 239 ]] ; then
        toRenameOrNotToRename=$( "$jHelper" -windowType hud -icon "$icon" -heading "Computer Name Setting" -description "$renameMessage" -button2 "Rename" -button1 "No Name" -timeout 300 )
        if [[ "$toRenameOrNotToRename" = 2 ]]; then
            prename=true
        fi
    fi

}

fn_askforNewComputerName () {

    newComputerName=$( sudo -u "$currentUser" /usr/bin/osascript -e 'display dialog "Please enter the new computer name" default answer "" with title "Set New Computer Name" with text buttons {"Cancel","OK"} default button 2' -e 'text returned of result' )
}


fn_Process_reEnrollmentMethodChecks () {
    ##check for and set the parameters for re enrollment 
    if [[ "$reEnrollmentMethodChecks" ]] ; then

        ##clear any previous checks
        /bin/rm /private/tmp/reEnrollmentMethod*

        if [[ "$reEnrollmentMethodChecks" == *"ask"* ]]; then ask=true ; fi
        if [[ "$reEnrollmentMethodChecks" == *"keep"* ]]; then keep=true ; fi
        if [[ "$reEnrollmentMethodChecks" == *"prename"* ]]; then prename=true ; fi

        ##write a placeholder so the re-enroll package create knows to create the ComputerName.txt file
        if [[ "$reEnrollmentMethodChecks" == *"splashbuddy"* ]]; then
            /usr/bin/touch /private/tmp/reEnrollmentMethod.splashbuddy
        fi ##re-enroll has splashbuddy
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# SYSTEM CHECKS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Caffeinate
/usr/bin/caffeinate -dis &
caffeinatePID=$!

##Get Current User
currentUser=$( /usr/bin/stat -f %Su /dev/console )

##Check if FileVault Enabled
fvStatus=$( /usr/bin/fdesetup status | head -1 )

##Run system requirement checks
validate_power_status
validate_free_space

##Don't waste the users time, exit here if system requirements are not met
if [[ "${#sysRequirementErrors[@]}" -ge 1 ]]; then
    /bin/echo "Launching jamfHelper Dialog (Requirements Not Met)..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$errorIcon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure your computer meets the following requirements:

$( /usr/bin/printf '\t• %s\n' "${sysRequirementErrors[@]}" )

If you continue to experience this issue, please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1

    cleanExit 1
fi

##This is the beginning of the re-enroll work-flow to handle the computer name
if [[ "$reEnrollmentMethodChecks" ]] && [[ $eraseInstall == 1 ]] && [[ "$autoPKGEnrollmentEventName" ]] ; then
    fn_Process_reEnrollmentMethodChecks

    /bin/echo "Script is configured for re-enrollment."

    ## if re-enrollment is enabled to ask what to do about the name
    currentComputerName=$( /usr/sbin/scutil --get ComputerName )

    if [[ $ask = true ]] && [[ ${currentUser} != "root" ]] ; then
        /bin/echo "Asking what to do about the computer name."
        fn_askWhatToDoForComputerName
    elif [[ $ask = true ]] && [[ ${currentUser} = "root" ]]; then
        #statements
        keep=true
        /bin/echo "The computer is at the login window. Defaulting to preserving the computer name."
    fi

    if [[ $keep = true ]]; then
        /bin/echo "Keeping the current computer name."
        newComputerName="$currentComputerName"
    fi 

    if [[ $prename = true ]]; then
        /bin/echo "Assigning a new computer name."
        fn_askforNewComputerName
    fi 

    # Computer name is assigned after eraseinstall
    if [[ "$newComputerName" ]]; then
        /bin/echo "Assigned computer name after eraseinstall: $newComputerName"
        /bin/echo "$newComputerName" > /private/tmp/reEnrollmentMethod.newComputerName.txt 
    fi 
fi # re-enrollment and erase install - prep for naming the computer after eraseinstall stage


##Check for existing OS installer
loopCount=0
while [ "$loopCount" -lt 3 ]; do
    if [ -e "$OSInstaller" ]; then
        /bin/echo "$OSInstaller found, checking version."
        OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
        /bin/echo "OSVersion is $OSVersion"
        if [ "$OSVersion" = "$version" ]; then
            /bin/echo "Installer found, version matches. Verifying checksum..."
            verifyChecksum
        else
            ##Delete old version.
            /bin/echo "Installer found, but old. Deleting..."
            /bin/rm -rf "$OSInstaller"
            /bin/sleep 2
            downloadInstaller
        fi
        if [ "$validChecksum" -eq 1 ]; then
            unsuccessfulDownload=0
            break
        fi
    else
        downloadInstaller
    fi
    unsuccessfulDownload=1
    ((loopCount++))
done

if [ "$unsuccessfulDownload" -eq 1 ]; then
    /bin/echo "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
    /bin/echo "Prompting user for error and exiting..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$errorIcon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1
    cleanExit 0
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CREATE FIRST BOOT SCRIPT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/mkdir -p /usr/local/jamfps

/bin/cat << EOF > "$finishOSInstallScriptFilePath"
#!/bin/bash
## First Run Script to remove the installer.
## Clean up files
/bin/rm -fr "$OSInstaller"
/bin/sleep 2
## Update Device Inventory
/usr/local/jamf/bin/jamf recon
## Remove LaunchAgent and LaunchDaemon
/bin/rm -f "$osinstallersetupdAgentSettingsFilePath"
/bin/rm -f "$osinstallersetupdDaemonSettingsFilePath"
## Remove Script
/bin/rm -fr /usr/local/jamfps
exit 0
EOF

/usr/sbin/chown root:admin "$finishOSInstallScriptFilePath"
/bin/chmod 755 "$finishOSInstallScriptFilePath"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH DAEMON
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/cat << EOF > "$osinstallersetupdDaemonSettingsFilePath"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfps.cleanupOSInstall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$finishOSInstallScriptFilePath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

##Set the permission on the file just made.
/usr/sbin/chown root:wheel "$osinstallersetupdDaemonSettingsFilePath"
/bin/chmod 644 "$osinstallersetupdDaemonSettingsFilePath"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH AGENT FOR FILEVAULT AUTHENTICATED REBOOTS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
if [ "$cancelFVAuthReboot" -eq 0 ]; then
    ##Determine Program Argument
    if [ "$osMajor" -ge 11 ]; then
        progArgument="osinstallersetupd"
    elif [ "$osMajor" -eq 10 ]; then
        progArgument="osinstallersetupplaind"
    fi

    /bin/cat << EOP > "$osinstallersetupdAgentSettingsFilePath"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.install.osinstallersetupd</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>MachServices</key>
    <dict>
        <key>com.apple.install.osinstallersetupd</key>
        <true/>
    </dict>
    <key>TimeOut</key>
    <integer>300</integer>
    <key>OnDemand</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
    </array>
</dict>
</plist>
EOP

    ##Set the permission on the file just made.
    /usr/sbin/chown root:wheel "$osinstallersetupdAgentSettingsFilePath"
    /bin/chmod 644 "$osinstallersetupdAgentSettingsFilePath"

fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# APPLICATION
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Launch jamfHelper
if [ "$userDialog" -eq 0 ]; then
    /bin/echo "Launching jamfHelper as FullScreen..."
    "$jHelper" -windowType fs -title "" -icon "$icon" -heading "$heading" -description "$description" &
    jamfHelperPID=$!
else
    /bin/echo "Launching jamfHelper as Utility Window..."
    "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "$heading" -description "$description" -iconSize 100 &
    jamfHelperPID=$!
fi

##Re-enrollment package creation stage
if [[ "$reEnrollmentMethodChecks" ]] && [[ $eraseInstall == 1 ]] || [[ "$autoPKGEnrollmentEventName" ]] && [[ $eraseInstall == 1 ]] ; then
    ##package creation 
    if [ "$versionMajor${versionMinor:=0}" -ge 134 ] ; then
        autoEnrollPKGResult=$( "$jamfBinary" policy -event "$autoPKGEnrollmentEventName" )
        /bin/echo "Results from package creation policy: $autoPKGEnrollmentEventName"
        /bin/echo "$autoEnrollPKGResult"

        ##Make and array of the packages built with 'productbuild' - For future ideas
        IFS=$'\n'
        productbuildPackages=($(/bin/echo "$autoEnrollPKGResult" | /usr/bin/grep productbuild | /usr/bin/awk -F 'Wrote product to ' '{ print $2 }'))
        unset IFS

        ##Built in support for multiple packages - For future ideas
        for packageName in "${productbuildPackages[@]}" ; do
            /bin/echo "Adding package $packageName to post install"
            installpackageOption+="--installpackage $packageName "
        done
    else
        echo "startosinstall with installpackage is not supported on this version $version"

        "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        Re-enrollment packages are not supported on $version. Minimum version is macOS 10.13.4" -iconSize 100 -button1 "OK" -defaultButton 1


        cleanExit 1
    fi

    ##Error Reporting for failing to create package
    # if [[ -z "${productbuildPackages[@]}" ]]; then 
    if [[ "${#productbuildPackages[@]}" = 0 ]]; then 
        /bin/echo "Error: Re-enrollment package cannot be found, failing out"


        if [[ "$autoEnrollPKGResult" == *"DEP Crossover"* ]] ; then
            "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        The Mac is assigned for Device Enrollment to a different Jamf Pro Server in Apple Business Manager." -iconSize 100 -button1 "OK" -defaultButton 1

        elif [[ "$autoEnrollPKGResult" == *"DEP multiple Jamf Pro"* ]] ; then
            "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        The Mac is assigned for Device Enrollment across multiple Jamf Pro Servers." -iconSize 100 -button1 "OK" -defaultButton 1

        elif [[ "$autoEnrollPKGResult" == *"failed to get invitationCode"* ]] ; then
            "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        Failed to generate invitationCode for the re-enrollment package." -iconSize 100 -button1 "OK" -defaultButton 1

        elif [[ "$autoEnrollPKGResult" == *"no JSS URL Will not create PKG"* ]] ; then
            "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        The package creation script is not configure correctly. No JSS URL configured." -iconSize 100 -button1 "OK" -defaultButton 1
        else
            "$jHelper" -windowType utility -title "$title" -icon "$icon" -heading "Re-enrollment Preparation Failed" -description "We were unable to prepare your computer for $macOSname with re-enrollment.

        Re-enrollment package could not be found." -iconSize 100 -button1 "OK" -defaultButton 1
        fi

        cleanExit 1
    fi
fi ##re-enrollment and erase install - re-enrollment package creation stage

##Load LaunchAgent
if [ "$fvStatus" = "FileVault is On." ] && \
   [ "$currentUser" != "root" ] && \
   [ "$cancelFVAuthReboot" -eq 0 ] ; then
    userID=$( /usr/bin/id -u "${currentUser}" )
    /bin/launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
fi

##Begin Upgrade
/bin/echo "Launching startosinstall..."

##Check if eraseInstall is Enabled
if [ "$eraseInstall" -eq 1 ]; then
    eraseopt='--eraseinstall'
    /bin/echo "Script is configured for Erase and Install of macOS."
fi

osinstallLogfile="/var/log/startosinstall.log"
if [ "$versionMajor" -ge 14 ]; then
    eval "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" "$installpackageOption" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" 2>&1 &
else
    eval "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" "$installpackageOption" --applicationpath "\"$OSInstaller\"" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" 2>&1 &
fi
/bin/sleep 3

cleanExit 0
