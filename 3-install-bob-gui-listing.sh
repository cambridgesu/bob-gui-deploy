#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI listing component


# Add the BOB-GUI software (the native voting component, without any setup management)
if [ ! -d ${installationRoot}/bob-gui ] ; then
        cd "${installationRoot}"
        git clone https://github.com/cusu/bob-gui.git
fi

# Ensure the additionalvotes folder is writable by the webserver
chown "${apacheUser}"."${webEditorsGroup}" "${installationRoot}"/bob-gui/bob/additionalvotescsv/
chmod g+w "${installationRoot}"/bob-gui/bob/additionalvotescsv/

# Install the house style if not already present; note that the "--strip 1" will remove the top-level directory in the .tgz
if [ ! -r "${installationRoot}"/bob-gui/public_html/style/header.html ] ; then
	if [ ! -r "${houseStylePackage}" ] ; then
		echo "ERROR: The house style package file specified in the deployment config is not present"
		exit 1
	fi
	tar -xf "${houseStylePackage}" --strip 1 -C ${installationRoot}/bob-gui/public_html/style/
	if [ ! -r "${installationRoot}"/bob-gui/public_html/style/header.html ] || [ ! -r "${installationRoot}"/bob-gui/public_html/style/footer.html ] ; then
		echo "ERROR: The house style package does not include a header file"
		rm ${installationRoot}/bob-gui/public_html/style/*
		exit
	fi
	chown nobody."${webEditorsGroup}" "${installationRoot}"/bob-gui/public_html/style/
	chmod g+w "${installationRoot}"/bob-gui/public_html/style/
fi

# Add the favicon, if required
if [ "${faviconObtainFromUrl}" ] ; then
	faviconFile="${installationRoot}"/bob-gui/public_html/favicon.ico
	if [ ! -r "${faviconFile}" ]; then
		wget -O "${faviconFile}" "${faviconObtainFromUrl}"
		chown nobody."${webEditorsGroup}" "${faviconFile}"
		chmod g+w "${faviconFile}"
	fi
fi

# Create the config file; it is harmless to leave the template in place
if [ ! -e "${installationRoot}"/bob-gui/config.php ] ; then
	cp -p "${installationRoot}"/bob-gui/config.php.template "${installationRoot}"/bob-gui/config.php
fi

# Add settings to the configuration
#!# Need to migrate each setting block to this new unified config
#!# Inconsistent namings here would be good to clear up
sed -i \
-e "s|^\$config\['liveServerUrl'.*|\$configIngest['liveServerUrl'] = 'https://${domainName}';|" \
-e "s/^\$config\['administratorEmail'.*/\$config['administratorEmail'] = '${serverAdmin}';/" \
-e "s/^\$config\['mailDomain'.*/\$config['mailDomain'] = '${mtaUserMailDomain}';/" \
-e "s/^\$config\['installerUsername'.*/\$config['installerUsername'] = '${installerUsername}';/" \
-e "s/^\$config\['installerPassword'.*/\$config['installerPassword'] = '${installerPassword}';/" \
-e "s/^\$config\['countingMethod'.*/\$configBob['countingMethod'] = '${countingMethod}';/" \
-e "s/^\$config\['organisationName'.*/\$config['organisationName'] = '${organisationName}';/" \
        "${installationRoot}"/bob-gui/config.php

# Convert some settings from boolean to string true/false, so PHP receives native boolean; ternary operator as at: http://stackoverflow.com/a/3953712
controlPanelLinkDirectly=$( $controlPanelLinkDirectly && echo 'true' || echo 'false')
disableListWhoVoted=$( $disableListWhoVoted && echo 'true' || echo 'false')

# Add the listing settings to the config file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
sed -i \
-e "s/.*configListing\['username'].*/\$configListing['username'] = '${bobDbListingUsername}';/" \
-e "s/.*configListing\['password'.*/\$configListing['password'] = '${bobDbListingPassword}';/" \
-e "s|.*configListing\['controlPanelUrl'.*|\$configListing['controlPanelUrl'] = '${controlPanelUrl}';|" \
-e "s/.*configListing\['controlPanelOnlyUsers'.*/\$configListing['controlPanelOnlyUsers'] = '${controlPanelOnlyUsers}';/" \
-e "s/.*configListing\['controlPanelLinkDirectly'.*/\$configListing['controlPanelLinkDirectly'] = ${controlPanelLinkDirectly};/" \
	"${installationRoot}"/bob-gui/config.php

# Add the BOB settings to the config file (replace the lines matching on the left with the whole config string on the right)
sed -i \
-e "s/.*configBob\['dbDatabase'.*/\$configBob['dbDatabase'] = '${bobDbDatabase}';/" \
-e "s/.*configBob\['dbPassword'.*/\$configBob['dbPassword'] = '${bobDbPassword}';/" \
-e "s/.*configBob\['dbUsername'.*/\$configBob['dbUsername'] = '${bobDbUsername}';/" \
-e "s/.*configBob\['dbSetupUsername'.*/\$configBob['dbSetupUsername'] = '${bobDbSetupUsername}';/" \
-e "s/.*configBob\['disableListWhoVoted'.*/\$configBob['disableListWhoVoted'] = ${disableListWhoVoted};/" \
	"${installationRoot}"/bob-gui/config.php

# Disable auto-count if required
if $disableAutoCount ; then
	sed -i -e "s/.*configBob\['countingInstallation'.*/\$configBob['countingInstallation'] = false;/" "${installationRoot}"/bob-gui/config.php
fi

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT ON ${bobDbDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"
${mysql} -e "GRANT SELECT ON ${bobDbIngestDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"

