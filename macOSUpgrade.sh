#!/bin/bash
##########################################################################################
#
#	Copyright (c) 2018 Jamf.  All rights reserved.
#
#		Redistribution and use in source and binary forms, with or without
#		modification, are permitted provided that the following conditions are met:
#		  * Redistributions of source code must retain the above copyright
#			notice, this list of conditions and the following disclaimer.
#		  * Redistributions in binary form must reproduce the above copyright
#			notice, this list of conditions and the following disclaimer in the
#			documentation and/or other materials provided with the distribution.
#		  * Neither the name of the Jamf nor the names of its contributors may be
#			used to endorse or promote products derived from this software without
#			specific prior written permission.
#
#		THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#		EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#		WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#		DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#		DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#		(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#		LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#		ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#		(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#		SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
##########################################################################################
#
#	SUPPORT FOR THIS PROGRAM
#		No support is offered
#
##########################################################################################
#
#	ABOUT THIS PROGRAM
#
#	NAME
#		macOSUpgrade.sh
#
#	SYNOPSIS
#		This script was designed to be used in a Self Service policy to ensure specific
#		requirements have been met before proceeding with an inplace upgrade of the macOS,
#		as well as to address changes Apple has made to the ability to complete macOS upgrades
#		silently.
#
##########################################################################################
#
#	REQUIREMENTS:
#		- Jamf Pro
#		- macOS Clients running version 10.10.5 or later
#		- macOS Installer 10.12.4 or later
#		- eraseInstall option is ONLY supported with macOS Installer 10.13.4+ and client-side macOS 10.13+
#		- Look over the USER VARIABLES and configure as needed.
#
#	HISTORY
#
#	Version is: YYYY/MM/DD @ HH:MMam/pm
#	Version is: 2018/09/13 @ 10:00am
#
#	- 2018/09/13 @ 10:00am by Jeff Rippy | Tennessee Tech University
#		- Modified for Tennessee Tech
#		- Github source: https://github.com/scifiman/macOSUpgrade
#	- 2018/04/30 by Joshua Roskos | Jamf
#		- Updated
#		- Version v2.6.1
#	- 2018/01/05 by Joshua Roskos | Jamf
#		- Initial Script
#		- Github source: https://github.com/kc9wwh/macOSUpgrade
# 
##########################################################################################
#
#	DEFINE VARIABLES & READ IN PARAMETERS
#
##########################################################################################

scriptName="macOSUpgrade"
date="$(date "+%Y%m%d.%H%M.%S")"
APPDIR="/Applications"
APP="${APPDIR}/Install macOS High Sierra.app"
AppVersionFile="${APP}/Contents/Info.plist"
DEBUG="FALSE"
logDir="/tmp/${scriptName}"
log="${logDir}/${scriptName}.log"
mountPoint=""
computerName=""
loggedInUsername=""
OSInstaller="${APP}"
downloadTrigger="some download trigger"
osMajor="$(/usr/bin/sw_vers -productVersion | awk -F. '{print $2}')"
osMinor="$(/usr/bin/sw_vers -productVersion | awk -F. '{print $3}')"
eraseInstall=0						# 0 = Disabled
									# 1 = Enabled (Factory Default)
									# Only valid for macOS installer 10.13.4+
									# Only valid for macOS Clients 10.13+
userDialog=0						# 0 = Full Screen
									# 1 = Utility Window
# This positions the dialog box for JamfHelper.
downloadPositionHUD="ur"	# Leave blank for a centered position

# The variables below here are set further in the script.
# They are declared here so they are in the global scope.
caffeinatePID=""
OSInstallerVersion=""
OSInstallESDChecksum=""
macOSname=""
title=""
heading=""
description=""
downloadDescription=""
macOSicon=""
	
##########################################################################################
# 
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
##########################################################################################

function finish()
{
	local exitStatus=$1
	[[ $exitStatus ]] || exitStatus=0
	echo "FINISH: ${log}" | tee -a "${log}"
	logger -f "${log}"
	mv "${log}" "${log}.${date}"
	kill ${caffeinatePID}
	exit $exitStatus
}

function warningMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	[[ $thisMessage ]] || thisMessage="Unknown Warning"
	echo "WARNING: (${thisCode}) ${thisMessage}" | tee -a "${log}"
}

function normalMessage()
{
	local thisMessage="$1"
	[[ $thisMessage ]] || return
	echo "${thisMessage}" | tee -a "${log}"
}

function errorMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	echo "ERROR: (${thisCode}) ${thisMessage}" | tee -a "${log}"
	finish "$thisCode"
}

function message()
{
	local thisCode=$1
	local thisMessage="$2"
	
	(( thisCode > 0 )) && errorMessage "$thisCode" "${thisMessage}"
	(( thisCode < 0 )) && warningMessage "$thisCode" "${thisMessage}"
	(( thisCode == 0 )) && normalMessage "${thisMessage}"
}

function downloadInstaller()
{
	message 0 "Downloading $macOSname Installer..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -windowPosition "$downloadPositionHUD" -title "$title" \
		-alignHeading "center" -alignDescription "left" -description \
		"$downloadDescription" -lockHUD -icon \
		"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" \
		-iconSize 100 &
    # Capture PID for Jamf Helper HUD
    jamfHUDPID=$!
    # Run policy to cache installer
    /usr/local/jamf/bin/jamf policy -event "$downloadTrigger"
    # Kill Jamf Helper HUD post download
    kill "${jamfHUDPID}"
}

function verifyChecksum()
{
	if [[ "$OSInstallESDChecksum" != "" ]]; then
		osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
		if [[ "$osChecksum" == "$OSInstallESDChecksum" ]]; then
			message 0 "Checksum: Valid"
			return
		else
			message 0 "Checksum: Not Valid"
			message 0 "Beginning new dowload of installer"
			/bin/rm -rf "$OSInstaller"
			sleep 2
			downloadInstaller
		fi
	else
		return
	fi
}

function createFirstBootScript()
{
	# This creates the First Boot Script to complete the install.
	/bin/mkdir -p /Library/Scripts/TTU/finishOSInstall
	cat << EOF > "/Library/Scripts/TTU/finishOSInstall/finishOSInstall.sh"
#!/bin/bash
# First Run Script to remove the installer.
# Clean up files
/bin/rm -fdr \"$OSInstaller\"
/bin/sleep 2
# Update Device Inventory
/usr/local/jamf/bin/jamf recon
# Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
# Remove Script
/bin/rm -fdr /Library/Scripts/TTU/finishOSInstall
exit 0
EOF

	/usr/sbin/chown root:admin /Library/Scripts/TTU/finishOSInstall/finishOSInstall.sh
	/bin/chmod 755 /Library/Scripts/TTU/finishOSInstall/finishOSInstall.sh
}

function createLaunchDaemonPlist()
{
	# This creates the plist file for the LaunchDaemon.
	cat << EOF > "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>edu.tntech.cleanupOSInstall</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>/Library/Scripts/TTU/finishOSInstall/finishOSInstall.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
	/bin/chmod 644 /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
}

function createFileVaultLaunchAgentRebootPlist()
{
	# If the drive is encrypted, create this LaunchAgent for authenticated reboots
	# Determine Program Argument
	if [[ $osMajor -ge 11 ]]; then
		progArgument="osinstallersetupd"
	elif [[ $osMajor -eq 10 ]]; then
		progArgument="osinstallersetupplaind"
	fi

	cat << EOF > "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"
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
	<integer>Aqua</integer>
	<key>OnDemand</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
	</array>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
}

function main()
{
	# For jss scripts, the following is true:
	# Variable $1 is defined as mount point
	# Variable $2 is defined as computer name
	# Variable $3 is defined as username (That is the currently logged in user or root if at the loginwindow.
	# These numbers change from 1-index to 0-index when put in an array.

	local argArray=()

	# Caffeinate
	/usr/bin/caffeinate -dis &
	caffeinatePID=$!

	# Verify arguments are passed in.  Otherwise exit.
	if [[ "$#" -eq 0 ]]; then
		message 99 "No parameters passed to script."	# We should never see this.
	else
		argArray=( "$@" )
	fi

	# Get the variables passed in and clean up if necessary.
	mountPoint="${argArray[0]}"
	[[ $DEBUG == TRUE ]] && message 0 "Mount Point BEFORE stripping a trailing slash (/) is $mountPoint."
	unset 'argArray[0]'	# Remove mountPoint from the argArray
	mountPoint="${mountPoint%/}"	# This removes a trailing '/' if present.
	[[ $DEBUG == TRUE ]] && message 0 "Mount Point AFTER stripping a trailing slash (/) is $mountPoint."

	computerName="${argArray[1]}"
	[[ $DEBUG == TRUE ]] && message 0 "Computer name is $computerName."
	unset 'argArray[1]'	# Remove computerName from the argArray

	loggedInUsername="${argArray[2]}"
	if [[ $loggedInUsername == "" ]]; then
		[[ $DEBUG == TRUE ]] && message 0 "No user currently logged in."
	else
		[[ $DEBUG == TRUE ]] && message 0 "Logged in Username is $loggedInUsername."
	fi
	unset 'argArray[2]'	# Remove loggedInUsername from the argArray

	# Specify path to OS installer. Use Parameter 4 in the JSS, or specify above in the variable list.
	OSInstallerTemp="${argArray[3]}"
	if [[ $OSInstallerTemp == "" ]]; then
		[[ $DEBUG == TRUE ]] && message 0 "No path to OSInstaller specified. Using default of ${OSInstaller}."
	else
		[[ $DEBUG == TRUE ]] && message 0 "OS Installer path is now $OSInstaller."
		OSInstaller="$OSInstallerTemp"
	fi
	unset 'argArray[3]'	# Remove OSInstaller from the argArray

	# Version of OS Installer. Use Parameter 5 in the JSS to specify.
	OSInstallerVersion="${argArray[4]}"
	if [[ $OSInstallerVersion == "" ]]; then
		[[ $DEBUG == TRUE ]] && message 0 "OS Installer Version specified as $OSInstallerVersion."
	else
		[[ $DEBUG == TRUE ]] && message 10 "No OS Installer Version specified. Please input the version of the installer that is being used."
	fi
	unset 'argArray[4]'	# Remove OSInstallerVersion from the argArray

	downloadTriggerTemp="${argArray[5]}"
	if [[ $downloadTriggerTemp == "" ]]; then
		[[ $DEBUG == TRUE ]] && message 0 "No download trigger specified.  Using default value $downloadTrigger."
	else
		[[ $DEBUG == TRUE ]] && message 0 "Specified download trigger is $downloadTrigger."
		downloadTrigger="$downloadTriggerTemp"
	fi
	unset 'argArray[5]'	# Remove downloadTriggerTemp from the argArray

	OSInstallESDChecksum="${argArray[6]}"
	if [[ $OSInstallESDChecksum == "" ]]; then
		[[ $DEBUG == TRUE ]] && message 0 "No InstallESD checksum specified."
	else
		[[ $DEBUG == TRUE ]] && message 0 "InstallESD checksum specified as $OSInstallESDChecksum."
	fi
	unset 'argArray[6]'	# Remove OSInstallESDChecksum from the argArray

	# Get title of the OS, i.e. macOS High Sierra
	# Use these values for the user dialog box
	macOSname="$(echo "$OSInstaller" | sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')"
	title="$macOSname Upgrade"	# This only applies to Utility Window, not Full Screen.
	heading="Please wait as your computer is prepared for $macOSname..."
	description="This process will take approximately 5-10 minutes. Once completed, your computer will reboot and begin the upgrade process."
	downloadDescription="The installer resources for $macOSname need to download to your computer before the upgrade process can begin.  Please allow this process approximately 30 minutes to complete.  Your download speeds may vary."
	# This positions the dialog box for JamfHelper.
	downloadPositionHUD="ur"	# Leave blank for a centered position
	macOSicon="$OSInstaller/Contents/Resources/InstallAssistant.icns"
	
	# Get Current User
	currentUser="$(stat -f %Su /dev/console)"

	# Check if FileVault Enabled
	fvStatus="$(/usr/bin/fdesetup status | head -1)"

	# Check if device is on battery or ac power
	pwrAdapter="$(/usr/bin/pmset -g ps)"
	if [[ ${pwrAdapter} == *"AC Power"* ]]; then
		pwrStatus="OK"
		message 0 "Power Check: OK - AC Power Detected"
	else
		pwrStatus="ERROR"
		message 0 "Power Check: ERROR - No AC Power Detected"
	fi

	# Check if free space > 15GB
	if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
		freeSpace=$(/usr/sbin/diskutil info / | grep "Available Space" | awk '{print $6}' | cut -c 2- )
	else
		freeSpace=$(/usr/sbin/diskutil info / | grep "Free Space" | awk '{print $6}' | cut -c 2- )
	fi

	if [[ ${freeSpace%.*} -ge 15000000000 ]]; then
		spaceStatus="OK"
		message 0 "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
	else
		spaceStatus="ERROR"
		message 0 "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
	fi

	# Check for existing OS installer
	loopCount=0
	while [[ $loopCount -lt 3 ]]; do
		if [[ -e "$OSInstaller" ]]; then
			message 0 "$OSInstaller found, checking version."
			OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
			message 0 "OSVersion is $OSVersion"
			if [[ $OSVersion == "$OSInstallerVersion" ]]; then
				message 0 "Installer found, version matches. Verifying checksum..."
				verifyChecksum
			else
				# Delete old version.
				message 0 "Installer found, but not the specified version. Deleting and downloading a new copy..."
				/bin/rm -rf "$OSInstaller"
				sleep 2
				downloadInstaller
			fi
			((loopCount++))
			if [[ $loopCount -ge 3 ]]; then
				message 0 "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
				message 0 "Prompting user for error and exiting..."
				/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the myTECH Helpdesk to report this error.  E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
				finish
			fi
		else
			downloadInstaller
		fi
	done

	createFirstBootScript
	createLaunchDaemonPlist
	createFileVaultLaunchAgentRebootPlist

	# Begin install.
	if [[ ${pwrStatus} == "OK" ]] && [[ ${spaceStatus} == "OK" ]]; then
		# Launch jamfHelper
		if [[ ${userDialog} == 0 ]]; then
			message 0 "Launching jamfHelper as FullScreen..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "" -icon "$macOSicon" -heading "$heading" -description "$description" &
			jamfHelperPID=$!
		fi

		if [[ ${userDialog} == 1 ]]; then
			message 0 "Launching jamfHelper as Utility Window..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "$heading" -description "$description" -iconSize 100 &
			jamfHelperPID=$!
		fi

		# Load LaunchAgent
		if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]; then
			userID="$(id -u "${currentUser}")"
			launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
		fi

		# Begin Upgrade
		message 0 "Launching startosinstall..."
		# Check if eraseInstall is Enabled
		if [[ $eraseInstall == 1 ]]; then
			message 0 "Script is configured for Erase and Install of macOS."
			"$OSInstaller/Contents/Resources/startosinstall" --applicationpath "$OSInstaller" --eraseinstall --nointeraction --pidtosignal "$jamfHelperPID" &
		else
			"$OSInstaller/Contents/Resources/startosinstall" --applicationpath "$OSInstaller" --nointeraction --pidtosignal "$jamfHelperPID" &
		fi
		/bin/sleep 3
	else
		# Remove Script
		/bin/rm -f "/Library/Scripts/TTU/finishOSInstall/finishOSInstall.sh"
		/bin/rm -f "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
		/bin/rm -f "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"

		message 0 "Launching jamfHelper Dialog (Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least 15GB of Free Space.

    If you continue to experience this issue, please contact the myTECH Helpdesk. E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
	fi
}

[[ ! -d "${logDir}" ]] && mkdir -p "${logDir}"
[[ $DEBUG == TRUE ]] && message 0 "Mode: DEBUG"
message 0 "BEGIN: ${log} ${date}"
main "$@"
finish