#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Generate an API key for the bestow mechanism
apiKey=`randpw`

# Ensure the log file is writable by the webserver
chown "${apacheUser}" "${documentRoot}"/bob-gui/controlpanel/logfile.txt

# Copy in the providers (directory) API
if [ ! -r "${providersApiFile}" ] ; then
	echo "ERROR: The providers API file is not present"
	exit 1
fi
if [ ! -e "${documentRoot}"/bob-gui/controlpanel/providers.php ] ; then
	cp "${providersApiFile}" "${documentRoot}"/bob-gui/controlpanel/providers.php
	chown bobguiIngest.$webEditorsGroup "${providersApiFile}"
	chmod g+rw "${providersApiFile}"
fi

# Enable the control panel, and add the control panel settings to the config file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
#!# disableListWhoVoted has a dependency on 3-install-bob-gui-listing.sh of this installer
sed -i \
-e "s/.*configControlpanel\['enabled'.*/\$configControlpanel['enabled'] = true;/" \
-e "s/.*configControlpanel\['username'.*/\$configControlpanel['username'] = '${bobDbControlpanelUsername}';/" \
-e "s/.*configControlpanel\['password'.*/\$configControlpanel['password'] = '${bobDbControlpanelPassword}';/" \
-e "s/.*configControlpanel\['administratorEmail'.*/\$configControlpanel['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*configControlpanel\['organisationName'.*/\$configControlpanel['organisationName'] = '${organisationName}';/" \
-e "s/.*configControlpanel\['mailDomain'.*/\$configControlpanel['mailDomain'] = '${mtaUserMailDomain}';/" \
-e "s/.*configControlpanel\['emailTech'.*/\$configControlpanel['emailTech'] = '${voteAdmin}';/" \
-e "s/.*configControlpanel\['emailReturningOfficerReceipts'.*/\$configControlpanel['emailReturningOfficerReceipts'] = '${emailReturningOfficerReceipts}';/" \
-e "s|.*configControlpanel\['liveServerUrl'.*|\$configControlpanel['liveServerUrl'] = 'https://${domainName}';|" \
-e "s|.*configControlpanel\['apiKey'.*|\$configControlpanel['apiKey'] = '${apiKey}';|" \
-e "s/.*configControlpanel\['disableListWhoVoted'.*/\$configControlpanel['disableListWhoVoted'] = ${disableListWhoVoted};/" \
-e "s/.*configControlpanel\['countingMethod'.*/\$configControlpanel['countingMethod'] = '${countingMethod}';/" \
-e "s/.*configControlpanel\['maximumOpeningDays'.*/\$configControlpanel['maximumOpeningDays'] = ${maximumOpeningDays};/" \
	"${documentRoot}"/bob-gui/config.php

# If testing, put the apiKey into the ingest configuration, so that they match
if [ $instanceDataApiKey == 'auto' ]; then
	sed -i \
	-e "s|.*configIngest\['instanceDataApiKey'.*|\$configIngest['instanceDataApiKey'] = '${apiKey}';|" \
		"${documentRoot}"/bob-gui/config.php
fi

# State the API key which may be useful for testing
echo "The API key that has been generated is ${apiKey}"

# Create the control panel database
${mysql} -e "CREATE DATABASE IF NOT EXISTS votescontrolpanel DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP ON votescontrolpanel.* TO '${bobDbControlpanelUsername}'@'localhost' IDENTIFIED BY '${bobDbControlpanelPassword}';"

# Create the instances table, by cloning the structure of the main instances table
${mysql} -e "CREATE TABLE IF NOT EXISTS votescontrolpanel.instances LIKE ${bobDbDatabase}.instances;"

