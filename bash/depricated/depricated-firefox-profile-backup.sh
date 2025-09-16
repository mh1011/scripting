#!/bin/bash

# A simple Bash script that backs up my Firefox profiles in two different locations


Date=$(date +"%b %d, %Y")
ProfileDirectory="/Firefox/Profile/Directory"
BackupDirectory1="/Backup/Directoty/1"
BackupDirectory2="/Backup/Directoty/2"
FirefoxProfiles=("Firefox Profile 1" "Firefox Profile 2" "Firefox Profile 3")

for Profile in "${FirefoxProfiles[@]}"; 
do
    # Backing Up on Location 1
    cp -arfp "$ProfileDirectory"/"$Profile" "$BackupDirectory1"
    mv $BackupDirectory1/"$Profile" $BackupDirectory1/"$Profile ($Date)"

    # Backing Up & Archiving on Location 2
    cp -arfp "$ProfileDirectory"/"$Profile" "$BackupDirectory2"
    cd "$ProfileDirectory"
    tar jcf "$BackupDirectory2"/"$Profile ($Date).tar.bz2" "$Profile"
    rm -rf "$BackupDirectory2"/"$Profile"
done
