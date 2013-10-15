#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Enable the Apache configuration
directive="Include ${documentRoot}/bob-gui/controlpanel/apache.conf"
perl -p -i -e "s|#${directive}|${directive}|gi" "${vhostFile}"
sudo /etc/init.d/apache2 restart

# Generate an API key for the bestow mechanism
apiKey=`randpw`

# Create the ingest bootstrap file; it is harmless to leave the template in place
if [ ! -e "${documentRoot}"/bob-gui/controlpanel/index.php ] ; then
	cp -p "${documentRoot}"/bob-gui/controlpanel/index.php.template "${documentRoot}"/bob-gui/controlpanel/index.php
fi

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

# Add the database credentials and other settings to the BOB control panel bootstrap file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
#!# disableListWhoVoted has a dependency on 3-install-bob-gui-listing.sh of this installer
sed -i \
-e "s/.*'username'.*/\$config['username'] = '${bobDbControlpanelUsername}';/" \
-e "s/.*'password'.*/\$config['password'] = '${bobDbControlpanelPassword}';/" \
-e "s/.*'administratorEmail'.*/\$config['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*'organisationName'.*/\$config['organisationName'] = '${organisationName}';/" \
-e "s/.*'mailDomain'.*/\$config['mailDomain'] = '${mtaUserMailDomain}';/" \
-e "s/.*'emailTech'.*/\$config['emailTech'] = '${voteAdmin}';/" \
-e "s/.*'emailReturningOfficerReceipts'.*/\$config['emailReturningOfficerReceipts'] = '${emailReturningOfficerReceipts}';/" \
-e "s|.*'liveServerUrl'.*|\$config['liveServerUrl'] = 'https://${domainName}';|" \
-e "s|.*'apiKey'.*|\$config['apiKey'] = '${apiKey}';|" \
-e "s/.*'disableListWhoVoted'.*/\$config['disableListWhoVoted'] = ${disableListWhoVoted};/" \
	"${documentRoot}"/bob-gui/controlpanel/index.php

# If testing, put the apiKey into the ingest configuration, so that they match
if [ $instanceDataApiKey == 'auto' ]; then
	sed -i \
	-e "s|.*'instanceDataApiKey'.*|\$config['instanceDataApiKey'] = '${apiKey}';|" \
		"${documentRoot}"/bob-gui/ingest/bobguiIngestWrapper.php
fi

# State the API key which may be useful for testing
echo "The API key that has been generated is ${apiKey}"

# Create the control panel database
${mysql} -e "CREATE DATABASE IF NOT EXISTS votescontrolpanel DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP ON votescontrolpanel.* TO '${bobDbControlpanelUsername}'@'localhost' IDENTIFIED BY '${bobDbControlpanelPassword}';"

# Create the instances table, by cloning the structure of the main instances table
${mysql} -e "CREATE TABLE IF NOT EXISTS votescontrolpanel.instances LIKE ${bobDbDatabase}.instances;"

