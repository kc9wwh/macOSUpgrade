# macOS Sierra Self Service Upgrade Process
###### Workflow for doing an in-place upgrade without user interaction.

___
This script was designed to be used in a Self Service policy to ensure specific requirements have been met before proceeding with an inplace upgrade to macOS Sierra, as well as to address changes Apple has made to the ability to complete macOS upgrades silently.

Requirements:
* Jamf Pro
* macOS Sierra Installer must be staged in /Users/Shared/


Written by: Joshua Roskos | Professional Services Engineer | Jamf

Created On: January 5th, 2017 | Updated On: February 14th, 2017

___

**Why is this needed?**

Starting with macOS Sierra, Apple has begun enforcing the way in which you can silently call for the OS upgrade process to happen in the background. Because of this change, many common ways that have been used and worked in the past no longer do. This script was created to adhear to Apple's requirements of the startosinstall binary. 

This script has been tested on OS X 10.11.5 upgrading to macOS Sierra 10.12.2 without issue. If the machine is FileVault encrypted, it will complete the authenticated restart to the OS Installer and automatically perform the upgrade with no user interaction. Upon completion the machine will again reboot to the macOS Sierra Login Window.


**Configuring the Script**

When you open the script you will find some user variables defined on lines 61-77. Here you can specify the message that is displayed to the end user while the script is running and preparing the computer to upgrade to macOS Sierra.

Also, if you decide not to stage the macOS Sierra Installer in /Users/Shared/, you will need to update the paths on lines 77 and 114. 


**Stagging macOS Sierra Installer**

In order for this script to work, you will have to have a copy of the macOS Sierra Installer that is available from the Mac App Store located in /Users/Shared/. One of the easiest ways to achieve this is to package the installer with composer as seen below and deploy the package via Jamf Pro.

![alt text](/imgs/composer.png)


**Example of Required Self Service Description**

![alt text](/imgs/selfservice.png)


**Example of FullScreen Dialog**

![alt text](/imgs/fullScreen.png)


**Example of Utility Dialog**

![alt text](/imgs/utility.png)
