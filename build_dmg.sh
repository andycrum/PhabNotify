#!/bin/bash

if [ -d /Volumes/PhabNotify/ ] ; then
	echo "/Volumes/PhabNotify already mounted, unmount it first"
	exit
fi

hdiutil create -size 32m -fs HFS+ -volname "PhabNotify" PhabNotify_tmp.dmg
hdiutil attach PhabNotify_tmp.dmg
cp -R DerivedData/PhabNotify/Build/Products/Release/PhabNotify.app /Volumes/PhabNotify/PhabNotify.app/
DEVS=$(hdiutil attach PhabNotify_tmp.dmg | cut -f 1)
DEV=$(echo $DEVS | cut -f 1 -d ' ')
hdiutil detach $DEV
hdiutil convert PhabNotify_tmp.dmg -format UDZO -o PhabNotifyRO.dmg
mv PhabNotifyRO.dmg PhabNotify.dmg
rm PhabNotify_tmp.dmg
