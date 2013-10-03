#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI ingesting (config transfer) component


# Install prerequisites
zypper -n install -l php-openssl

# Create a user account which will do the ingesting
id -u bobguiIngest &>/dev/null || useradd bobguiIngest

# Create a writable log file
ingestLogFile="$documentRoot"/bob-gui/ingest/bobguiIngestLog.txt
touch $ingestLogFile
chown bobguiIngest.$webEditorsGroup $ingestLogFile
chmod g+rw $ingestLogFile

# Ensure the lockfile directory is writable
ingestLockDirectory="$documentRoot"/bob-gui/ingest/lock
chown bobguiIngest.$webEditorsGroup $ingestLockDirectory
chmod g+rw $ingestLockDirectory

# Create the ingest bootstrap file; it is harmless to leave the template in place
if [ ! -e "${documentRoot}"/bob-gui/ingest/bobguiIngestWrapper.php ] ; then
	cp -p "${documentRoot}"/bob-gui/ingest/bobguiIngestWrapper.php.template "${documentRoot}"/bob-gui/ingest/bobguiIngestWrapper.php
fi

# Add the database credentials and other settings to the BOB ingest bootstrap file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
sed -i \
-e "s/.*'databaseStaging'.*/\$config['databaseStaging'] = '${bobDbIngestDatabase}';/" \
-e "s/.*'databaseLive'.*/\$config['databaseLive'] = '${bobDbDatabase}';/" \
-e "s/.*'username'.*/\$config['username'] = '${bobDbIngestUsername}';/" \
-e "s/.*'password'.*/\$config['password'] = '${bobDbIngestPassword}';/" \
-e "s/.*'administratorEmail'.*/\$config['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*'organisationName'.*/\$config['organisationName'] = '${organisationName}';/" \
-e "s/.*'smsRecipient'.*/\$config['smsRecipient'] = '${smsRecipient}';/" \
-e "s/.*'smsApiKey'.*/\$config['smsApiKey'] = '${smsApiKey}';/" \
-e "s|.*'instanceDataUrl'.*|\$config['instanceDataUrl'] = '${instanceDataUrl}';|" \
-e "s|.*'liveServerUrl'.*|\$config['liveServerUrl'] = 'https://${domainName}';|" \
	"${documentRoot}"/bob-gui/ingest/bobguiIngestWrapper.php

# Create the staging database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${bobDbIngestDatabase} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,DELETE,CREATE,ALTER,DROP ON ${bobDbIngestDatabase}.* TO '${bobDbIngestUsername}'@'localhost' IDENTIFIED BY '${bobDbIngestPassword}';"
${mysql} -e "GRANT SELECT,INSERT,CREATE ON ${bobDbDatabase}.* TO '${bobDbIngestUsername}'@'localhost' IDENTIFIED BY '${bobDbIngestPassword}';"



# todo:

# Install hourly cron job

