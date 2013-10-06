#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Enable the Apache configuration
directive="Include ${documentRoot}/bob-gui/controlpanel/apache.conf"
perl -p -i -e "s|#${directive}|${directive}|gi" "${vhostFile}"
sudo /etc/init.d/apache2 restart

# Create the ingest bootstrap file; it is harmless to leave the template in place
if [ ! -e "${documentRoot}"/bob-gui/controlpanel/index.php ] ; then
	cp -p "${documentRoot}"/bob-gui/controlpanel/index.php.template "${documentRoot}"/bob-gui/controlpanel/index.php
fi

# Add the database credentials and other settings to the BOB control panel bootstrap file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# Escaping needs to be dealt with properly
sed -i \
-e "s/.*'username'.*/\$config['username'] = '${bobDbControlpanelUsername}';/" \
-e "s/.*'password'.*/\$config['password'] = '${bobDbControlpanelPassword}';/" \
-e "s/.*'administratorEmail'.*/\$config['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*'emailTech'.*/\$config['emailTech'] = '${voteAdmin}';/" \
-e "s/.*'emailReturningOfficerReceipts'.*/\$config['emailReturningOfficerReceipts'] = '${emailReturningOfficerReceipts}';/" \
-e "s|.*'liveServerUrl'.*|\$config['liveServerUrl'] = 'https://${domainName}';|" \
	"${documentRoot}"/bob-gui/controlpanel/index.php

