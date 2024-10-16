#!/bin/bash

# Name: DMGcontrol
# Description: A bash script that can be used to automate the installation of macOS apps from DMG files. Can be used via MDM (tested with Jamf Pro).
# Author: Jared Schwager
# Date: 2024-10-16
# Version: 0.5.0
# License: Apache License 2.0
# Usage: ./DMGcontrol.sh
# Dependencies: swiftDialog

# Check for current logged-in user
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
echo "Logged-in user is $loggedInUser"

# Pull in Jamf parameters, or specify your inputs below
appName=$4
downloadURL=$5
killProcess=$6
icon=$7

# Specify temporary DMG mount path
dmgPath="/private/tmp/$appName.dmg"

# Download latest version of installer
echo "Downloading latest version of $appName from $downloadURL"
curl -L "$downloadURL" --output "$dmgPath"

# Mount Installer DMG
echo "Mounting DMG..."
mountOutput=$(hdiutil attach "$dmgPath" -nobrowse)
echo "$mountOutput"

# Extract the device identifier, mounted volume, and app bundle name
mountedDevice=$(echo "$mountOutput" | grep -i "$appName" | grep -E "^\/dev\/disk.+\/Volumes.+$" | grep -Eo "^\/dev\/disk\S+")
echo "Mounted device is $mountedDevice"
mountedVolume=$(echo "$mountOutput" | grep -Eo "\/Volumes\/.+$")
echo "Mounted volume is $mountedVolume"
appBundle=$(ls "$mountedVolume" | grep ".app")
echo "Discovered app bundle $appBundle in $mountedVolume"

# Check if installed version is already up-to-date
if [[ -e "/Applications/$appBundle" ]]; then
    dmgAppVersion=$(defaults read "$mountedVolume/$appBundle/Contents/Info.plist" CFBundleShortVersionString)
    installedAppVersion=$(defaults read "/Applications/$appBundle/Contents/Info.plist" CFBundleShortVersionString)
    if [[ "$dmgAppVersion" == "$installedAppVersion" ]]; then
        echo "The app is already installed and up-to-date!"
        exit 0
    fi
fi

# Check if any app processes are running (case-insensitive)
if pgrep -i "$killProcess" > /dev/null; then
    echo "$appName is running, prompting user to kill processes"
    relaunchApp=true

    # Prompt user to kill running app processes
    dialog --small --title "$appName install/update pending" --message "Please click the button below to quit $appName and continue the installation process." --button1text "Quit $appName" --timer 1800 --icon "$icon" --moveable --ontop
    
    # Kill all running app processes (case-insensitive)
    pkill -i $killProcess
else
    echo "$appName is not running, proceeding"
fi

# Move application from mounted DMG to /Applications, delete any prior instances of app from /Applications and /Users/x/Applications
echo "Copying app bundle from mounted DMG to /Applications"
if [ -e "/Applications/$appBundle" ]; then
    echo "Removing /Applications/$appBundle"
    rm -rf "/Applications/$appBundle"
fi
if [ -e "/Users/$loggedInUser/Applications/$appBundle" ]; then
    echo "Removing /Users/$loggedInUser/Applications/$appBundle"
    rm -rf "/Users/$loggedInUser/Applications/$appBundle"
fi
cp -Rp "$mountedVolume/$appBundle" "/Applications/"

# Unmount the DMG
echo "Unmounting $mountedDevice"
hdiutil detach $mountedDevice -force

# Cleanup temporary DMG
rm -rf $dmgPath

# Prompt user to relaunch app if it was previously running during the update process
if [[ "$relaunchApp" = true ]]; then
    dialog --small --title "$appName install/update completed" --message "$appName update process has completed. You will need to open the app again to begin using the updated version." --button1text "Okay" --timer 1800 --icon "$icon" --moveable --ontop
fi

# Check for app install, exit accordingly
if [[ -e "/Applications/$appBundle" ]]; then
    echo "$appName installed successfully!"
    exit 0
else
    echo "$appBundle was not found in the /Applications directory and thus failed to install."
    exit 1
fi