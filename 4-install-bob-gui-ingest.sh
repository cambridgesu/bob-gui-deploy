#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI ingesting (config transfer) component


# Create a user account which will do the ingesting
ingestUser=bobguiIngest
id -u $ingestUser &>/dev/null || useradd $ingestUser

# Create a writable log file
ingestLogFile="$installationRoot"/bob-gui/ingest/bobguiIngestLog.txt
touch $ingestLogFile
chown bobguiIngest.$webEditorsGroup $ingestLogFile
chmod g+rw $ingestLogFile

# Ensure the lockfile directory is writable
ingestLockDirectory="$installationRoot"/bob-gui/ingest/lock
chown bobguiIngest.$webEditorsGroup $ingestLockDirectory
chmod g+rw $ingestLockDirectory

# Create the staging database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${databaseStaging} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create the staging instances table based on the live instances table
${mysql} -e "CREATE TABLE IF NOT EXISTS ${databaseStaging}.instances LIKE ${databaseLive}.instances;";
${mysql} -e "INSERT INTO ${databaseStaging}.instances SELECT * FROM ${databaseLive}.instances;";

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,DELETE,CREATE,ALTER,DROP ON ${databaseStaging}.* TO '${ingestUsername}'@'localhost' IDENTIFIED BY '${ingestPassword}';"
${mysql} -e "GRANT SELECT,INSERT,CREATE                   ON ${databaseLive}.*    TO '${ingestUsername}'@'localhost' IDENTIFIED BY '${ingestPassword}';"

# Allow listing to read from the ingest database, now we have confirmed we are using an ingest setup
${mysql} -e "GRANT SELECT ON ${databaseStaging}.instances TO '${listingUsername}'@'localhost' IDENTIFIED BY '${listingPassword}';"

# Allow live BOB to read from the ingest database, now we have confirmed we are using an ingest setup
#!# Need to audit why BOB insists on "exactly select,insert,update" rather than just select here
${mysql} -e "GRANT SELECT,INSERT,UPDATE ON ${databaseStaging}.* TO '${dbUsername}'@'localhost' IDENTIFIED BY '${dbPassword}';"
${mysql} -e "GRANT SELECT ON ${databaseStaging}.* TO '${dbSetupUsername}'@'localhost';"

# Add the hourly cron job to the (root) cron.d, running as the ingest user; see the .cron.example file
# NB Some systems like Ubuntu are very picky about /etc/cron.d/ jobs: 644, owned by root, and not contain characters like .-_
cronJob="30 * * * * ${ingestUser} php -d memory_limit=700M ${installationRoot}/bob-gui/ingest/index.php"
echo "${cronJob}" > /etc/cron.d/bobguiIngest
chmod 644 /etc/cron.d/bobguiIngest

