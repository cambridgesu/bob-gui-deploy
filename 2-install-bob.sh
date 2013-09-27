#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the voting component (BOB)


# Add the BOB software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob ] ; then
	cd "${documentRoot}"
	git clone git@github.com:cusu/bob.git
fi


# MTA (mail sending)
# Useful guides for Postfix at: http://www-uxsup.csx.cam.ac.uk/~fanf2/hermes/doc/misc/postfix.html and http://www-co.ch.cam.ac.uk/facilities/clusters/theory/heartofgold/heartofgold-postfix.html

zypper -n install -l postfix
if [ "${mtaRelayhost}" ] ; then
	if ! grep -qF "${mtaRelayhost}" /etc/postfix/main.cf ; then
	        echo $'\nrelayhost = '"${mtaRelayhost}" >> /etc/postfix/main.cf
	fi
fi
# The canonical config should be something like the following (uncommented) :
# wwwrun         vote.admin@example.com
# @machinename   @example.com
if ! grep -qF "${apacheUser}" /etc/postfix/canonical ; then
	echo $'\n'"${apacheUser}	${voteAdmin}" >> /etc/postfix/canonical
fi
if ! grep -qF "@${HOSTNAME}" /etc/postfix/canonical ; then
	echo $'\n'"@${HOSTNAME}	@${mtaUserMailDomain}" >> /etc/postfix/canonical
fi
postmap /etc/postfix/canonical
postfix reload

# Put the database password into the BOB native password file
#!# This should be supplied as an option rather than require a file to be loaded
echo -n "${bobDbPassword}" > "${documentRoot}"/bob/dbpass

# Create the voting database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${bobDbDatabase} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the users if they do not exist); see: https://github.com/cusu/bob/blob/master/BOB.php#L1436
${mysql} -e "GRANT SELECT,INSERT,UPDATE ON ${bobDbDatabase}.* TO '${bobDbUsername}'@'localhost'      IDENTIFIED BY '${bobDbPassword}';"
${mysql} -e "GRANT SELECT,CREATE        ON ${bobDbDatabase}.* TO '${bobDbSetupUsername}'@'localhost' IDENTIFIED BY '${bobDbPassword}';"

# Install (download) OpenSTV, the STV counting program
if [ ! -d ${documentRoot}/openstv ] ; then
	cd "${documentRoot}"
	wget https://github.com/cusu/openSTV/blob/master/SourceCode/OpenSTV-1.6-2_original.tar.gz?raw=true
	tar xvzf OpenSTV-1.6-2_original.tar.gz
	mv OpenSTV-1.6/openstv .
	rm -rf OpenSTV-1.6
	rm OpenSTV-1.6-2_original.tar.gz
fi

