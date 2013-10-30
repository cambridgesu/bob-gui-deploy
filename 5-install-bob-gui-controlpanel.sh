#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Install PHP's mbstring() if available (recommended); if not available, emulated conversion of any incoming non-UTF8 strings to UTF8 using ISO using iconv is in place
set +e
zypper -n install -l php5-mbstring
set -e

# Generate an API key for the bestow mechanism
apiKey=`randpw`

# Ensure the log file is writable by the webserver
chown "${apacheUser}" "${installationRoot}"/bob-gui/controlpanel/logfile.txt

# Copy in the providers (directory) API
if [ ! -r "${providersApiFile}" ] ; then
	echo "ERROR: The providers API file is not present"
	exit 1
fi
if [ ! -e "${installationRoot}"/bob-gui/controlpanel/providers.php ] ; then
	cp "${providersApiFile}" "${installationRoot}"/bob-gui/controlpanel/providers.php
	chown bobguiIngest.$webEditorsGroup "${providersApiFile}"
	chmod g+rw "${providersApiFile}"
fi

# Limit to specific users by adding an .htaccess file
if [ -n "$controlPanelOnlyUsers" ]; then
	echo "Require User ${controlPanelOnlyUsers}" > "${installationRoot}"/bob-gui/public_html/controlpanel/.htaccess
fi

# Convert some settings from boolean to string true/false, so PHP receives native boolean; ternary operator as at: http://stackoverflow.com/a/3953712
disableSurnameForenameRequirement=$( $disableSurnameForenameRequirement && echo 'true' || echo 'false')
disableRonAvailability=$( $disableRonAvailability && echo 'true' || echo 'false')

# Enable the control panel, and add the control panel settings to the config file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
#!# disableListWhoVoted has a dependency on 3-install-bob-gui-listing.sh of this installer
sed -i \
-e "s/.*configControlpanel\['enabled'.*/\$configControlpanel['enabled'] = true;/" \
-e "s/.*configControlpanel\['username'.*/\$configControlpanel['username'] = '${bobDbControlpanelUsername}';/" \
-e "s/.*configControlpanel\['password'.*/\$configControlpanel['password'] = '${bobDbControlpanelPassword}';/" \
-e "s/.*configControlpanel\['emailTech'.*/\$configControlpanel['emailTech'] = '${voteAdmin}';/" \
-e "s/.*configControlpanel\['emailReturningOfficerReceipts'.*/\$configControlpanel['emailReturningOfficerReceipts'] = '${emailReturningOfficerReceipts}';/" \
-e "s|.*configControlpanel\['apiKey'.*|\$configControlpanel['apiKey'] = '${apiKey}';|" \
-e "s/.*configControlpanel\['disableListWhoVoted'.*/\$configControlpanel['disableListWhoVoted'] = ${disableListWhoVoted};/" \
-e "s/.*configControlpanel\['maximumOpeningDays'.*/\$configControlpanel['maximumOpeningDays'] = ${maximumOpeningDays};/" \
-e "s/.*configControlpanel\['disableSurnameForenameRequirement'.*/\$configControlpanel['disableSurnameForenameRequirement'] = ${disableSurnameForenameRequirement};/" \
-e "s/.*configControlpanel\['disableRonAvailability'.*/\$configControlpanel['disableRonAvailability'] = ${disableRonAvailability};/" \
	"${installationRoot}"/bob-gui/config.php

# If testing, put the apiKey into the ingest configuration, so that they match
if [ $instanceDataApiKey == 'auto' ]; then
	sed -i \
	-e "s|.*configIngest\['instanceDataApiKey'.*|\$configIngest['instanceDataApiKey'] = '${apiKey}';|" \
		"${installationRoot}"/bob-gui/config.php
fi

# State the API key which may be useful for testing
echo "The API key that has been generated is ${apiKey}"

# Create the control panel database
${mysql} -e "CREATE DATABASE IF NOT EXISTS votescontrolpanel DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP ON votescontrolpanel.* TO '${bobDbControlpanelUsername}'@'localhost' IDENTIFIED BY '${bobDbControlpanelPassword}';"


