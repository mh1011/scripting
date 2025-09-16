#!/bin/bash

# A simple bash script that checks for a number of specific files
# in a specified folder and deletes the oldest file

# Here 'Count' checks for 5 files
Count="5"
Date=$(date +"%b %d, %Y (%a) %I:%M %p")
OldestFile=$(ls -rt1 /Folder/To/Check/ |  head -n 1);
# ExtenTion = File with extention like *.pdf
CheckFileCount=$(ls -l /Folder/To/Check/*.ExtenTion | egrep -c '^-');

if [ "$CheckFileCount" -le "$Count" ]; then
    echo "Less than 5 Files"
    echo -e $Date '\t' '\t' "Not Enough Files">> /Log/File/Reports.log;
    echo "Log written on /Log/File/Reports.log"
    echo "Exiting ..."
else
    echo "More than 5 Files"
    echo "Deleting the oldest file"
    # Actions
    rm $OldestFile
    echo -e $Date '\t' '\t' $OldestFile >> /Log/File/Reports.log;
    echo "Log written on /Log/File/Reports.log"
fi
