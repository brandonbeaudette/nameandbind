#!/bin/bash
#check run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

#Set last 6 serial number
LAST6SN=`ioreg -k IOPlatformSerialNumber | sed -En 's/^.*"IOPlatformSerialNumber".*(.{6})"$/\1/p'` 

#set window size
printf '\e[8;30;120t'

#splash screen
clear
echo
echo "					NAME AND BIND (version 6)"
echo
echo "				*********************************************"
echo "				*                                           *"
echo "				*                Attention                  *"
echo "				*                                           *"
echo "				*********************************************"
echo

#warning
echo "			This script will do the following:"
echo "			- offer to change the computer name"
echo "			- offer to change the Managed Software Center Client Identifier"
echo "			- remove admin and macadmin accounts ONLY if techies account is present"
echo "			- remove Open Directory binding and HomeSync files"
echo "			- change the login screen to username and password"
echo "			- bind or unbind the machine to or from AD"
echo "			- convert an existing local user account to an AD user account"
echo
echo " 		*remember to 'CMD-drag' the HomeSync icon from the menu in the user's account after removal*"
echo
echo "			DO NOT RUN THIS FROM AN END-USER ACCOUNT; ONLY FROM A LOCAL ADMIN"
echo
echo "			YOU NEED TO BE A DOMAIN ADMIN TO BIND OR UNBIND"
echo
read -p "Press ENTER to continue or CTRL + C to exit"
clear

#show hostname for reference
echo "The computer name is:"
scutil --get HostName
sleep 1

#option to change name
echo
echo "Do you want to change the computer name? y/n"
read keepname
if [ $keepname == y ]; then

	#START code to change name
	echo "OK...Let's change the name"

	#set computertype
	echo
	echo "What type of computer is this? (enter number)"
	echo "1-teacher laptop    2-administrators   3-lab   4-other staff"
	read computertype
		if [ $computertype -eq 1 ]; then
			computertype=T
		elif [ $computertype -eq 2 ]; then
			computertype=A
		elif [ $computertype -eq 4 ]; then
			computertype=S
		else
			echo "Enter lab number (1, 2, 3, etc) if the school has multiple labs"
			read labnumber
			computertype=$labnumber
		fi

	#set IRM and pad to 5 digits
	echo
	echo "Enter the IRM tag number:"
	read fIRM
	IRM=`printf %05d $fIRM`

	#set bigschoolname
	echo
	echo "Enter the school abbreviation (dist, bms, gshs, sop, etc):"
	read bigschoolname

	#change school to a 3-letter abbreviation
	schoolname=$(echo $bigschoolname | awk '{print toupper($0)}' | sed -e 's/.*\"\(.*\)\"/\1/' | cut -c '1-3')

	#set teachername
	echo
	echo "Enter the computer user's AD username (jdoe, bsmith, etc)"
	echo "or the lab machine #"
	read teachername

	#change names
	echo
	echo "Changing computer names..."
	sleep 2
	sudo scutil --set HostName "$schoolname$computertype$LAST6SN$IRM$teachername"
	sudo scutil --set LocalHostName "$schoolname$computertype$LAST6SN$IRM$teachername"
	sudo scutil --set ComputerName "$schoolname$computertype$LAST6SN$IRM$teachername"
	echo "New name is"
	Hostname
	#END code to change name

else
	echo "OK...keeping the name"
fi
sleep 2

#check MSC ClientID
clear
echo "The current Managed Software Center ClientIdentifier is:"
defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier
echo
echo "Would you like to change it? y/n"
read keepid
if [ $keepid == y ]; then

	#change MSC ClientID
	echo "OK...changing Managed Software Center ClientIdentifier"
	echo
	echo "Enter the new ClientIdentifier value (case sensitive):"
	read newmscid
	echo
	echo "OK...changing the value..."
	sudo defaults write /Library/Preferences/ManagedInstalls.plist ClientIdentifier $newmscid
	sleep 2
	echo "The new value is:"
	defaults read /Library/Preferences/ManagedInstalls.plist ClientIdentifier

	#Code to keep MSC ClientID
else
	echo "OK...keeping the existing Managed Software Center ClientIdentifier"
fi
sleep 2

#Delete generic admin accounts if techies is present
restech="`dscl . -list /Users |grep techies`"
resadm="`dscl . -list /Users |grep -w admin`"
resmac="`dscl . -list /Users |grep macadmin`"
clear
echo "Checking for generic admin accounts to delete"
echo
read -p "Press ENTER to continue or CTRL + C to exit"
echo
if [ "$restech" != "" ]; then
	echo "Techies account is present. Checking for admin and macadmin accounts. REBOOT if accounts removed"
	echo
	sleep 2
	#delete admin
		if [ "$resadm" != "" ]; then
			dscl . delete /Users/admin && rm -Rf /Users/admin && echo "admin removed...REBOOT WHEN FINISHED"
		else 
				echo "No admin account present...moving on"
		fi
	sleep 2

	#delete macadmin
		if [ "$resmac" != "" ]; then
			dscl . delete /Users/macadmin && rm -Rf /Users/macadmin && echo "macadmin removed...REBOOT WHEN FINISHED"
		else 
			echo "No macadmin account present...moving on"
		fi
	sleep 2
else
	echo "No Techies account on this machine. No generic admin accounts deleted."
fi

#verify need to continue
echo
echo "To continue to HomeSync removal press y, or press n to skip it and proceed to AD Binding"
read cont1
if [ $cont1 == y ]; then
	echo "Moving forward..."
	sleep 2
	clear

	#ask for user account to chown later; set moduser
	echo "Which user account is being removed from HomeSync?"
	echo "-press ENTER if none"
	echo
	ls /Users/
	read oduser
	echo

	#unbind from dox
	echo "Removing OD binding..."
	echo "-this will return an error if no existing binding"
	sleep 1
	dsconfigldap -r "dox.rfsd.k12.co.us"
	dscl /Search -delete / CSPSearchPath /LDAPv3/"dox.rfsd.k12.co.us"
	dscl /Search/Contacts -delete / CSPSearchPath /LDAPv3/"dox.rfsd.k12.co.us"

	#remove HomeSync
	echo
	echo "Removing HomeSync files..."
	sleep 1
	rm -Rf /Users/$oduser/.FileSync
	rm -Rf /Users/$oduser/Library/FileSync
	rm -Rf /Users/$oduser/Library/Preferences/com.apple.homeSync.plist
	echo "Finished with HomeSync file removal."
else
		echo "Skipping HomeSync removal..."
fi
sleep 2
echo
echo "Starting AD Bind Process..."
read -p "Press ENTER to continue or CTRL + C to exit"
clear

#verify teachername exists
if [ -z "$teachername" ]; then
	#future-insert sed statement to set teachername to 16th digit onward so no input needed
	#future-would need to make sure above value is AD username
	echo "Enter computer user's AD username or lab machine #" && read teachername
fi
sleep 2
clear

#test network
echo "Checking network connection..."
echo "pinging the domain controller..."
ping -c4 rfsddc1.rfsd.local > /dev/null 2>&1
if [ $? -eq 0 ]
then
  echo "Network is OK."
else
  echo "Unable to contact domain controller. AD Bind will not work. Exiting..." && exit
	sleep 2
fi

#check for existing AD binding
echo
echo "Checking for an existing binding..."
sleep 2
testadverify=`dsconfigad -show | awk 'FNR == 1 { print $5 }'`
if [ "$testadverify" != rfsd.local ]; then
	echo "Verified no existing AD bind"
else
	echo "This machine is bound and needs to be unbound. This may take a minute..."
	echo "Enter your AD Domain Admin username"
	read adremuser
	sudo dsconfigad -remove -username $adremuser
	adremuser=gone
fi
sleep 2

#check for existing binding again and exit on failure
echo
echo "Checking for an existing binding again..."
sleep 2
testadverify2=`dsconfigad -show | awk 'FNR == 1 { print $5 }'`
if [ "$testadverify2" != rfsd.local ]; then
	echo "Verified no existing AD bind"
else
	echo "This machine is still bound. Unbind via System Preferences" && exit
fi
sleep 2

#change login to username and password
echo
echo "Changing login screen and binding to AD..."
read -p "Press ENTER to continue or CTRL + C to exit"
defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true
 
#get name for AD binding
computerid=`/usr/sbin/scutil --get HostName | cut -c 1-15` 
 
#bind to AD
clear
echo "Binding to AD..."
echo "This may take a minute..."
echo "Enter your Domain Admin username"
read dausername
sudo dsconfigad -add rfsd.local -username $dausername -computer $computerid -force -passinterval 0 -preferred rfsddc1.rfsd.local -mobile enable -mobileconfirm disable -localhome enable -useuncpath enable -groups "Domain Admins,SchoolTech,ComTech,DistTech"
dausername=gone

#test AD binding
echo
echo "Testing AD binding..."
sleep 2
adverify=`dsconfigad -show | awk 'FNR == 1 { print $5 }'`
if [ $adverify == rfsd.local ]; then
	echo "The binding looks good."
else
		echo "Binding did not work. You need to troubleshoot and re-run the script. If an ADAM machine, check Network settings for DNS and " && exit
fi
sleep 2

#exit if no oduser value
echo
if [ -z $oduser ]; then
	echo "AD binding complete...Have a nice day."
	echo
	exit 0
else
	echo "Continuing..."
fi

#remove user account, rename, and change permissions
echo
echo "Removing user account but keeping files then changing file ownership..."
echo "-AD user account must be logged in on a wire immediately after this script to recreate account."
read -p "Press ENTER to continue or CTRL + C to exit" 
sudo dscl . delete /Users/$oduser
echo
echo "Changing file ownership with verbose output"
echo "This may fail for a minute or two...be patient"
echo
sleep 4

if [ $oduser != $teachername ]; then
	sudo mv -f /Users/$oduser /Users/$teachername
fi

# run chown until completes but exit after 60 failures
n=0
until [ $n -ge 60 ]
do
	sudo chown -Rv $teachername:RFSD\\Domain\ Users /Users/$teachername && break
	n=$[$n+1] && echo "failed...trying again...be patient"
	sleep 1
done

#verify file ownership change
rc=$?
if [[ $rc = 0 ]]
then
	echo "Permission change successful."
else
		echo "If you migrated a user account from OD to AD, something went wrong"
		echo 'Run this:sudo chown -Rv [username]:RFSD\\\\Domain\ Users /Users/[username]'
		echo "If you just bound to AD without converting an OD user, everything is OK" && exit
fi

#final advice
echo
echo "If you didn't get any unexplained errors, you are done."
echo
echo "Next, login with the user's AD account credentials WHILE ON A WIRED CONNECTION"
echo "in order to create the user's mobile AD account on top of the existing user files."
echo
echo "If you get the 'System unable to unlock login keychain' pop-up when logging in,"
echo "and the old user account password is known, choose 'Update Keychain' and use the"
echo "old user account password to unlock and update the login keychain."
echo
echo "If the old user account password is known but not available at the moment,"
echo "choose 'Continue to login'. You'll keep the existing keychain but have to click"
echo "through a lot of keychain requests. When old user account password is available,"
echo "open Keychain Access, select Login keychain, rt-click and Change Password."
echo
echo "Otherwise, choose 'Create New' which deletes the old user account login keychain"
exit 0