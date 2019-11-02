#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI listing component


# Add the BOB-GUI software (the native voting component, without any setup management)
if [ ! -d ${installationRoot}/bob-gui ] ; then
	cd "${installationRoot}"
	git clone https://github.com/cusu/bob-gui.git
	cd "${SCRIPTDIRECTORY}"
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

# Standardise names (i.e. move from BOB context to listing context)
databaseLive=$dbDatabase
databaseStaging=$dbDatabaseStaging

# Convert some settings from boolean to string true/false, so PHP receives native boolean; ternary operator as at: http://stackoverflow.com/a/3953712
controlPanelLinkDirectly=$( $controlPanelLinkDirectly && echo 'true' || echo 'false')
disableListWhoVoted=$( $disableListWhoVoted && echo 'true' || echo 'false')
disableSurnameForenameRequirement=$( $disableSurnameForenameRequirement && echo 'true' || echo 'false')
disableRonAvailability=$( $disableRonAvailability && echo 'true' || echo 'false')
voterReceiptDisableable=$( $voterReceiptDisableable && echo 'true' || echo 'false')
singleOrganisationMode=$( $singleOrganisationMode && echo 'true' || echo 'false')

# Convert domainName to liveServerUrl
liveServerUrl=https://${domainName}

# Add settings to the configuration
#!# Escaping needs to be dealt with properly
sed -i \
-e "s|^\$config\['liveServerUrl'.*|\$config['liveServerUrl'] = '${liveServerUrl}';|" \
-e "s/^\$config\['administratorEmail'.*/\$config['administratorEmail'] = '${administratorEmail}';/" \
-e "s/^\$config\['emailTech'.*/\$config['emailTech'] = '${emailTech}';/" \
-e "s/^\$config\['emailReturningOfficerReceipts'.*/\$config['emailReturningOfficerReceipts'] = '${emailReturningOfficerReceipts}';/" \
-e "s/^\$config\['mailDomain'.*/\$config['mailDomain'] = '${mailDomain}';/" \
-e "s/^\$config\['dbHostname'.*/\$config['dbHostname'] = '${dbHostname}';/" \
-e "s/^\$config\['dbDatabase'.*/\$config['dbDatabase'] = '${dbDatabase}';/" \
-e "s/^\$config\['dbDatabaseStaging'.*/\$config['dbDatabaseStaging'] = '${dbDatabaseStaging}';/" \
-e "s/^\$config\['dbUsername'.*/\$config['dbUsername'] = '${dbUsername}';/" \
-e "s/^\$config\['dbSetupUsername'.*/\$config['dbSetupUsername'] = '${dbSetupUsername}';/" \
-e "s/^\$config\['dbPassword'.*/\$config['dbPassword'] = '${dbPassword}';/" \
-e "s/^\$config\['listingUsername'.*/\$config['listingUsername'] = '${listingUsername}';/" \
-e "s/^\$config\['listingPassword'.*/\$config['listingPassword'] = '${listingPassword}';/" \
-e "s/^\$config\['ingestUsername'.*/\$config['ingestUsername'] = '${ingestUsername}';/" \
-e "s/^\$config\['ingestPassword'.*/\$config['ingestPassword'] = '${ingestPassword}';/" \
-e "s/^\$config\['controlpanelUsername'.*/\$config['controlpanelUsername'] = '${controlpanelUsername}';/" \
-e "s/^\$config\['controlpanelPassword'.*/\$config['controlpanelPassword'] = '${controlpanelPassword}';/" \
-e "s/^\$config\['installerUsername'.*/\$config['installerUsername'] = '${installerUsername}';/" \
-e "s/^\$config\['installerPassword'.*/\$config['installerPassword'] = '${installerPassword}';/" \
-e "s/^\$config\['voterReceiptDisableable'.*/\$config['voterReceiptDisableable'] = ${voterReceiptDisableable};/" \
-e "s/^\$config\['countingMethod'.*/\$config['countingMethod'] = '${countingMethod}';/" \
-e "s|^\$config\['countingInstallation'.*|\$config['countingInstallation'] = '${countingInstallation}';|" \
-e "s/^\$config\['disableListWhoVoted'.*/\$config['disableListWhoVoted'] = ${disableListWhoVoted};/" \
-e "s/^\$config\['organisationName'.*/\$config['organisationName'] = '${organisationName}';/" \
-e "s|^\$config\['controlPanelUrl'.*|\$config['controlPanelUrl'] = '${controlPanelUrl}';|" \
-e "s/^\$config\['controlPanelOnlyUsers'.*/\$config['controlPanelOnlyUsers'] = '${controlPanelOnlyUsers}';/" \
-e "s/^\$config\['controlPanelLinkDirectly'.*/\$config['controlPanelLinkDirectly'] = ${controlPanelLinkDirectly};/" \
-e "s/^\$config\['maximumOpeningDays'.*/\$config['maximumOpeningDays'] = ${maximumOpeningDays};/" \
-e "s/^\$config\['disableSurnameForenameRequirement'.*/\$config['disableSurnameForenameRequirement'] = ${disableSurnameForenameRequirement};/" \
-e "s/^\$config\['disableRonAvailability'.*/\$config['disableRonAvailability'] = ${disableRonAvailability};/" \
-e "s|^\$config\['instanceDataUrl'.*|\$config['instanceDataUrl'] = '${instanceDataUrl}';|" \
-e "s|^\$config\['instanceDataApiKey'.*|\$config['instanceDataApiKey'] = '${instanceDataApiKey}';|" \
-e "s/^\$config\['databaseStaging'.*/\$config['databaseStaging'] = '${databaseStaging}';/" \
-e "s/^\$config\['databaseLive'.*/\$config['databaseLive'] = '${databaseLive}';/" \
-e "s/^\$config\['smsRecipient'.*/\$config['smsRecipient'] = '${smsRecipient}';/" \
-e "s/^\$config\['smsApiKey'.*/\$config['smsApiKey'] = '${smsApiKey}';/" \
-e "s|^\$config\['listingWelcomeMessageHtml'.*|\$config['listingWelcomeMessageHtml'] = '${listingWelcomeMessageHtml}';|" \
-e "s/^\$config\['singleOrganisationMode'.*/\$config['singleOrganisationMode'] = ${singleOrganisationMode};/" \
        "${installationRoot}"/bob-gui/config.php

# Disable auto-count if required - this overwrites the default setting
if [ "$disableAutoCount" = true ] ; then
	sed -i -e "s/^\$config\['countingInstallation'.*/\$config['countingInstallation'] = false;/" "${installationRoot}"/bob-gui/config.php
fi

# Create the instances table; this structure should be in sync with that defined in BOB.php, with the GUI fields noted there uncommented
${mysql} -e "
CREATE TABLE IF NOT EXISTS ${databaseLive}.instances (
   id varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Generated globally-unique ID',
   url varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Computed URL location of this ballot',
   academicYear varchar(5) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Computed academic year string',
   urlSlug varchar(20) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Unique identifier for this ballot',
   provider varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Provider name',
   organisation varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Organisation name',
   title varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Title of this ballot',
   urlMoreInfo varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'URL for more info about the ballot',
   frontPageMessageHtml text COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'Optional front-page message',
   afterVoteMessageHtml text COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'An extra message, if any, which people will see when they have voted',
   emailReturningOfficer varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Returning Officer / mailbox',
   emailTech varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Technical Administrator',
   officialsUsernames varchar(255) COLLATE utf8_unicode_ci NOT NULL COMMENT 'Usernames of Returning Officer + Sysadmins',
   randomisationInfo enum('','Candidate order has been automatically randomised','Candidate order has been automatically alphabetised','Candidates have been entered by the Returning Officer in the order shown') COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'Candidate ordering/randomisation',
   organisationName varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'Organisation name',
   organisationUrl varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'Organisation URL',
   organisationLogoUrl varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL COMMENT 'URL of organisation''s logo',
   addRon enum('','Yes','No') COLLATE utf8_unicode_ci NOT NULL COMMENT 'Should Re-Open Nominations (RON) be automatically added as an additional candidate in each election?',
   electionInfo text COLLATE utf8_unicode_ci NOT NULL COMMENT 'Election info: Number of positions being elected; Position title; Names of candidates; each block separated by one line break',
   electionInfoAsEntered text COLLATE utf8_unicode_ci NOT NULL COMMENT 'Election info',
   referendumThresholdPercent int(2) DEFAULT '10' COMMENT 'Percentage of voters who must cast a vote in a referendum for the referendum to be countable',
   ballotStart datetime NOT NULL COMMENT 'Start date/time of the ballot',
   ballotEnd datetime NOT NULL COMMENT 'End date/time of the ballot',
   paperVotingEnd datetime DEFAULT NULL COMMENT 'End time of paper voting, if paper voting is also taking place',
   ballotViewableDelayed datetime DEFAULT NULL COMMENT 'End date/time for delayed viewing of results by voters',
   instanceCompleteTimestamp datetime DEFAULT NULL COMMENT 'Timestamp for when the instance (configuration and voters list) is complete',
   PRIMARY KEY  (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
";

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT ON ${databaseLive}.instances    TO '${listingUsername}'@'localhost' IDENTIFIED BY '${listingPassword}';"

