#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the voting component (BOB)


# Add the BOB software (the native voting component, without any setup management)
if [ ! -d ${installationRoot}/bob ] ; then
	cd "${installationRoot}"
	git clone https://github.com/cusu/bob.git
	cd "${SCRIPTDIRECTORY}"
fi

# MTA (mail sending)
# Useful guides for Postfix at: http://www-uxsup.csx.cam.ac.uk/~fanf2/hermes/doc/misc/postfix.html and http://www-co.ch.cam.ac.uk/facilities/clusters/theory/heartofgold/heartofgold-postfix.html
sudo apt-get install -y postfix
if [ "${mtaRelayhost}" ] ; then
	if ! grep -qF "${mtaRelayhost}" /etc/postfix/main.cf ; then
	        echo $'\nrelayhost = '"${mtaRelayhost}" >> /etc/postfix/main.cf
	fi
fi
# The canonical config should be something like the following (uncommented) :
# wwwrun         evote@example.com
# @machinename   @example.com
#!# Needs to check for existence of file also
if ! grep -qF "${apacheUser}" /etc/postfix/canonical ; then
	echo $'\n'"${apacheUser}	${emailTech}" >> /etc/postfix/canonical
fi
if ! grep -qF "@${HOSTNAME}" /etc/postfix/canonical ; then
	echo $'\n'"@${HOSTNAME}	@${mailDomain}" >> /etc/postfix/canonical
fi
postmap /etc/postfix/canonical
postfix reload
#? service postfix restart

# Create the voting database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${dbDatabase} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the users if they do not exist); see: https://github.com/cusu/bob/blob/master/BOB.php#L1436
# NB Staging permission also will be created later if using the ingest module
${mysql} -e "GRANT SELECT,INSERT,UPDATE ON ${dbDatabase}.* TO '${dbUsername}'@'localhost'      IDENTIFIED BY '${dbPassword}';"
${mysql} -e "GRANT SELECT,CREATE        ON ${dbDatabase}.* TO '${dbSetupUsername}'@'localhost' IDENTIFIED BY '${dbPassword}';"

# Install (download) OpenSTV, the STV counting program
sudo apt-get install -y python
if [ ! -d ${installationRoot}/openstv ] ; then
	cd "${installationRoot}"
	git clone https://github.com/cusu/openstv.git
	cd "${SCRIPTDIRECTORY}"
fi

