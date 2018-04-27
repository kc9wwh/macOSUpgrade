# macOS Self Service Upgrade Process
###### Workflow for doing an in-place upgrade without user interaction.

![OS X 10.10 Client Tested](https://img.shields.io/badge/OS%20X%2010.10-OK-brightgreen.svg)
![OS X 10.11 Client Tested](https://img.shields.io/badge/OS%20X%2010.11-OK-brightgreen.svg)
![OS X 10.12 Client Tested](https://img.shields.io/badge/OS%20X%2010.12-OK-brightgreen.svg)
![macOS 10.13 Client Tested](https://img.shields.io/badge/macOS%2010.13-OK-brightgreen.svg)
![OS X 10.12 Installer Tested](https://img.shields.io/badge/Sierra%20Installer-10.12.4%2B-yellow.svg)
![macOS 10.13 Installer Tested](https://img.shields.io/badge/High%20Sierra%20Installer-OK-brightgreen.svg)
___
This script was designed to be used in a Self Service policy to ensure specific requirements have been met before proceeding with an inplace upgrade to macOS, as well as to address changes Apple has made to the ability to complete macOS upgrades silently.

Requirements:
* Jamf Pro
* macOS Clients on 10.10.5 or later
* macOS Installer 10.12.4 or later
* Look over the USER VARIABLES and configure as needed.

___

**Why is this needed?**

Starting with macOS Sierra, Apple has begun enforcing the way in which you can silently call for the OS upgrade process to happen in the background. Because of this change, many common ways that have been used and worked in the past no longer do. This script was created to adhere to Apple's requirements of the startosinstall binary.

*This script has been tested on OS X 10.10.5, 10.11.5 and macOS 10.12.5 clients upgrading to 10.12.6 and 10.13.3. As of v2.5 of this script FileVault Authenticated reboots work again!*


**Configuring the Script**

When you open the script you will find some user variables defined on lines 60-99. Here you can specify the message that is displayed to the end user while the script is running and preparing the computer to upgrade to macOS Sierra, as well as the variables used to determine the version and path for the macOS Installer. Also, don't forget to setup a policy with a custom trigger specified as defined in the user variables.


**Staging the macOS Installer**

In order for this script to work, you will have to have a copy of the macOS Installer that is available from the Mac App Store located in /Applications. One of the easiest ways to achieve this is to package the installer with composer as seen below and deploy the package via Jamf Pro.

![alt text](/imgs/composer.png)


**Example of Required Self Service Description**

![alt text](/imgs/selfservice.png)


**Example of FullScreen Dialog**

![alt text](/imgs/fullScreen.png)


**Example of Utility Dialog**

![alt text](/imgs/utility.png)
