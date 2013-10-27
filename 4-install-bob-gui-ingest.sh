#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI ingesting (config transfer) component


# Install prerequisites
zypper -n install -l php-openssl

# Create a user account which will do the ingesting
ingestUser=bobguiIngest
id -u bobguiIngest &>/dev/null || useradd $ingestUser

# Create a writable log file
ingestLogFile="$installationRoot"/bob-gui/ingest/bobguiIngestLog.txt
touch $ingestLogFile
chown bobguiIngest.$webEditorsGroup $ingestLogFile
chmod g+rw $ingestLogFile

# Ensure the lockfile directory is writable
ingestLockDirectory="$installationRoot"/bob-gui/ingest/lock
chown bobguiIngest.$webEditorsGroup $ingestLockDirectory
chmod g+rw $ingestLockDirectory

# Add the ingest settings to the config file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
sed -i \
-e "s/.*configIngest\['databaseStaging'.*/\$configIngest['databaseStaging'] = '${bobDbIngestDatabase}';/" \
-e "s/.*configIngest\['databaseLive'.*/\$configIngest['databaseLive'] = '${bobDbDatabase}';/" \
-e "s/.*configIngest\['username'.*/\$configIngest['username'] = '${bobDbIngestUsername}';/" \
-e "s/.*configIngest\['password'.*/\$configIngest['password'] = '${bobDbIngestPassword}';/" \
-e "s/.*configIngest\['administratorEmail'.*/\$configIngest['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*configIngest\['organisationName'.*/\$configIngest['organisationName'] = '${organisationName}';/" \
-e "s/.*configIngest\['smsRecipient'.*/\$configIngest['smsRecipient'] = '${smsRecipient}';/" \
-e "s/.*configIngest\['smsApiKey'.*/\$configIngest['smsApiKey'] = '${smsApiKey}';/" \
-e "s|.*configIngest\['instanceDataUrl'.*|\$configIngest['instanceDataUrl'] = '${instanceDataUrl}';|" \
-e "s|.*configIngest\['instanceDataApiKey'.*|\$configIngest['instanceDataApiKey'] = '${instanceDataApiKey}';|" \
-e "s|.*configIngest\['liveServerUrl'.*|\$configIngest['liveServerUrl'] = 'https://${domainName}';|" \
	"${installationRoot}"/bob-gui/config.php

# Create the staging database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${bobDbIngestDatabase} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,DELETE,CREATE,ALTER,DROP ON ${bobDbIngestDatabase}.* TO '${bobDbIngestUsername}'@'localhost' IDENTIFIED BY '${bobDbIngestPassword}';"
${mysql} -e "GRANT SELECT,INSERT,CREATE ON ${bobDbDatabase}.* TO '${bobDbIngestUsername}'@'localhost' IDENTIFIED BY '${bobDbIngestPassword}';"

# Create the instances table, by cloning the structure of the main instances table
${mysql} -e "CREATE TABLE IF NOT EXISTS ${bobDbIngestDatabase}.instances LIKE ${bobDbDatabase}.instances;"

# Allow live BOB to read from the ingest database, now we have confirmed we are using an ingest setup
#!# Need to audit why BOB insists on "exactly select,insert,update" rather than just select here
${mysql} -e "GRANT SELECT,INSERT,UPDATE ON ${bobDbIngestDatabase}.* TO '${bobDbUsername}'@'localhost' IDENTIFIED BY '${bobDbPassword}';"

# Add the hourly cron job to the (root) cron.d, running as the ingest user; see the .cron.example file
cronJob="30 * * * * su ${ingestUser} -c 'php -d memory_limit=700M ${installationRoot}/bob-gui/ingest/index.php'"
echo "${cronJob}" > /etc/cron.d/bobguiIngest.cron

