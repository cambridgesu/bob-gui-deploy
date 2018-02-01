#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Install PHP's mbstring() if available (recommended); if not available, emulated conversion of any incoming non-UTF8 strings to UTF8 using ISO using iconv is in place
set +e
zypper -n install -l php53-mbstring
set -e

# Ensure the log file is writable by the webserver
chown "${apacheUser}" "${installationRoot}"/bob-gui/controlpanel/logfile.txt

# Copy in the providers (directory) API
if [ ! -r "${providersApiFile}" ] ; then
	echo "ERROR: The providers API file is not present"
	exit 1
fi
if [ ! -e "${installationRoot}"/bob-gui/controlpanel/providers.php ] ; then
	cp "${providersApiFile}" "${installationRoot}"/bob-gui/controlpanel/providers.php
	chown "${apacheUser}"."${webEditorsGroup}" "${providersApiFile}"
	chmod g+rw "${providersApiFile}"
fi

# Limit to specific users by adding an .htaccess file
if [ -n "$controlPanelOnlyUsers" ]; then
	echo "Require User ${controlPanelOnlyUsers}" > "${installationRoot}"/bob-gui/public_html/controlpanel/.htaccess
fi

# Enable the control panel module at application level
sed -i -e "s/^\$config\['enabled'.*/\$config['enabled'] = true;/" "${installationRoot}"/bob-gui/config.php

# Enable the control panel module at webserver level
sed -i -e "s/#Use MacroVotingControlpanel/Use MacroVotingControlpanel/" "${apacheVhostsConfigDirectory}/${domainName}.conf"

# Generate an API key for the bestow mechanism
apiKey=`randpw`

# Add the API key to the config
#!# apiKey should be renamed for clarity - this refers to key that the bestow end point emits with
sed -i -e "s|^\$config\['apiKey'.*|\$config['apiKey'] = '${apiKey}';|" "${installationRoot}"/bob-gui/config.php

# If testing, put the apiKey into the ingest configuration, so that they match
if [ $instanceDataApiKey == 'auto' ]; then
	sed -i -e "s|^\$config\['instanceDataApiKey'.*|\$config['instanceDataApiKey'] = '${apiKey}';|" "${installationRoot}"/bob-gui/config.php
fi

# State the API key which may be useful for testing
echo "The API key that has been generated is ${apiKey}"

# Create the control panel database
${mysql} -e "CREATE DATABASE IF NOT EXISTS votescontrolpanel DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP ON votescontrolpanel.* TO '${controlpanelUsername}'@'localhost' IDENTIFIED BY '${controlpanelPassword}';"


