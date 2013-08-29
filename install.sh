#!/bin/bash

# Script to install Rootkit Hunter
# Author: Márk Sági-Kazár (sagikazarmark@gmail.com)
# This script installs Rootkit Hunter on several Linux distributions.
#
# Version: 1.4.0

# Variable definitions
DIR=$(cd `dirname $0` && pwd)
NAME="Rootkit Hunter"
SLUG="rkhunter"
VER="1.4.0"
DEPENDENCIES=("tar")
TMP="/tmp/$SLUG"
INSTALL_LOG="$TMP/install.log"
ERROR_LOG="$TMP/error.log"

# Cleaning up
rm -rf $TMP
mkdir -p $TMP
cd $TMP
chmod 777 $TMP


# Basic function definitions

## Echo colored text
e()
{
	local color="\033[${2:-34}m"
	local log="${3:-$INSTALL_LOG}"
	echo -e "$color$1\033[0m"
	log "$1" "$log"
}

## Exit error
ee()
{
	local exit_code="${2:-1}"
	local color="${3:-31}"

	clear
	e "$1" "$color" "$ERROR_LOG"
	exit $exit_code
}

## Log messages
log()
{
	local log="${2:-$INSTALL_LOG}"
	echo "$1" >> "$log"
}

## Add dependency
dep()
{
	if [ ! -z "$1" ]; then
		DEPENDENCIES+=("$1")
	fi
}


# Checking root access
if [ $EUID -ne 0 ]; then
	ee "This script has to be ran as root!"
fi

# CTRL_C trap
ctrl_c()
{
	clear
	echo
	echo "Installation aborted by user!"
	cleanup
}
trap ctrl_c INT

# Basic checks

## Check for wget or curl or fetch
e "Checking for HTTP client..."
if [ `which curl 2> /dev/null` ]; then
	download="$(which curl) -s -O"
elif [ `which wget 2> /dev/null` ]; then
	download="$(which wget) --no-certificate"
elif [ `which fetch 2> /dev/null` ]; then
	download="$(which fetch)"
else
	dep "wget"
	download="$(which wget) --no-certificate"
	e "No HTTP client found, wget added to dependencies" 31
fi

## Check for package manager (apt or yum)
e "Checking for package manager..."
if [ `which apt-get 2> /dev/null` ]; then
	install[0]="apt"
	install[1]="$(which apt-get) -y --force-yes install"
elif [ `which yum 2> /dev/null` ]; then
	install[0]="yum"
	install[1]="$(which yum) -y install"
else
	ee "No package manager found."
fi

## Check for package manager (dpkg or rpm)
if [ `which dpkg 2> /dev/null` ]; then
	install[2]="dpkg"
	install[3]="$(which dpkg)"
elif [ `which rpm 2> /dev/null` ]; then
	install[2]="rpm"
	install[3]="$(which rpm)"
else
	ee "No package manager found."
fi


# Function definitions

## Install required packages
install()
{
	[ -z "$1" ] && { e "No package passed" 31; return 1; }

	e "Installing package: $1"
	${install[1]} "$1" >> $INSTALL_LOG 2>> $ERROR_LOG || ee "Installing $1 failed"
	e "Package $1 successfully installed"

	return 0
}

## Check installed package
check()
{
	[ -z "$1" ] && { e "No package passed" 31; return 2; }

	case ${install[2]} in
		dpkg )
			${install[3]} -s "$1" &> /dev/null
			;;
		rpm )
			${install[3]} -qa | grep "$1"  &> /dev/null
			;;
	esac
	return $?
}

## Download required file
download()
{
	[ -z "$1" ] && { e "No package passed" 31; return 1; }

	local text="${2:-files}"
	e "Downloading $text"
	$download "$1" >> $INSTALL_LOG 2>> $ERROR_LOG || ee "Downloading $text failed"
	e "Downloading $text finished"
	return 0
}

## Cleanup files
cleanup()
{
	cd $TMP 2> /dev/null || return 1
	find * -not -name '*.log' | xargs rm -rf
}


[ -z "$1" ] && ee "Please pass an email address as an argument"


# Adding dependencies
case ${install[2]} in
	dpkg )
		dep "mailutils"
		;;
	rpm )
		dep "mailx"
		;;
esac

# Checking dependencies
for dep in ${DEPENDENCIES[@]}; do
	check "$dep"
	[ $? -eq 0 ] || install "$dep"
done



if [ -f $DIR/rkhunter-1.4.0.tar.gz ]; then
	cp $DIR/rkhunter-1.4.0.tar.gz $TMP
else
	download http://ncu.dl.sourceforge.net/project/rkhunter/rkhunter/1.4.0/rkhunter-1.4.0.tar.gz "$NAME $VER files"
fi

e "Installing $NAME $VER"

tar -xzf rkhunter-1.4.0.tar.gz >> $INSTALL_LOG 2>> $ERROR_LOG
cd rkhunter-1.4.0

sh installer.sh --layout default --install >> $INSTALL_LOG 2>> $ERROR_LOG || ee "Installing $NAME $VER failed"

e "Updating database"
/usr/local/bin/rkhunter --update  >> $INSTALL_LOG 2>> $ERROR_LOG || e "Updating database failed" 31
/usr/local/bin/rkhunter --propupd  >> $INSTALL_LOG 2>> $ERROR_LOG || e "Updating database failed" 31

e "Installing cron script"
echo "#!/bin/sh
(
	/usr/local/bin/rkhunter --versioncheck
	/usr/local/bin/rkhunter --update
	/usr/local/bin/rkhunter --cronjob --report-warnings-only
) | /bin/mail -s 'rkhunter Daily Run ($(hostname))' $1" >> /etc/cron.daily/rkhunter.sh
chmod 755 /etc/cron.daily/rkhunter.sh

clear

e "Cleaning up"
cleanup

e "It is recommended to run a scan on the file system by running rkhunter --check"

if [ -s $ERROR_LOG ]; then
	e "Error log is not empty. Please check $ERROR_LOG for further details." 31
fi

e "Installation done."
