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

# Convert some settings from boolean to string true/false, so PHP receives native boolean; ternary operator as at: http://stackoverflow.com/a/3953712
controlPanelLinkDirectly=$( $controlPanelLinkDirectly && echo 'true' || echo 'false')
disableListWhoVoted=$( $disableListWhoVoted && echo 'true' || echo 'false')

# Add the listing settings to the config file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
sed -i \
-e "s/.*configListing\['configListing['username'].*/\$configListing['username'] = '${bobDbListingUsername}';/" \
-e "s/.*configListing\['password'.*/\$configListing['password'] = '${bobDbListingPassword}';/" \
-e "s/.*configListing\['administratorEmail'.*/\$configListing['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*configListing\['organisationName'.*/\$configListing['organisationName'] = '${organisationName}';/" \
-e "s/.*configListing\['mailDomain'.*/\$configListing['mailDomain'] = '${mtaUserMailDomain}';/" \
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
-e "s/.*configBob\['countingMethod'.*/\$configBob['countingMethod'] = '${countingMethod}';/" \
	"${installationRoot}"/bob-gui/config.php

# Disable auto-count if required
if $disableAutoCount ; then
	sed -i -e "s/.*configBob\['countingInstallation'.*/\$configBob['countingInstallation'] = false;/" "${installationRoot}"/bob-gui/config.php
fi

# Set up the instances table
cat > /tmp/instances.sql << \EOF
CREATE TABLE IF NOT EXISTS `instances` (
  `id` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Generated globally-unique ID',
  `url` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Computed URL location of this ballot',
  `academicYear` varchar(5) collate utf8_unicode_ci NOT NULL COMMENT 'Computed academic year string',
  `urlSlug` varchar(20) collate utf8_unicode_ci NOT NULL COMMENT 'Unique identifier for this ballot',
  `provider` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Provider name',
  `organisation` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Organisation name',
  `title` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Title of this ballot',
  `urlMoreInfo` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'URL for more info about the ballot',
  `frontPageMessageHtml` text collate utf8_unicode_ci default NULL COMMENT 'Optional front-page message',
  `afterVoteMessageHtml` text collate utf8_unicode_ci default NULL COMMENT 'An extra message, if any, which people will see when they have voted',
  `emailReturningOfficer` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Returning Officer / mailbox',
  `emailTech` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Technical Administrator',
  `officialsUsernames` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Usernames of Returning Officer + Sysadmins',
  `randomisationInfo` enum('','Candidate order has been automatically randomised','Candidate order has been automatically alphabetised','Candidates have been entered by the Returning Officer in the order shown') collate utf8_unicode_ci default NULL COMMENT 'Candidate ordering/randomisation',
  `organisationName` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'Organisation name',
  `organisationUrl` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'Organisation URL',
  `organisationLogoUrl` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'URL of organisation''s logo',
  `addRon` enum('','Yes','No') collate utf8_unicode_ci NOT NULL COMMENT 'Should Re-Open Nominations (RON) be automatically added as an additional candidate in each election?',
  `electionInfo` text collate utf8_unicode_ci NOT NULL COMMENT 'Election info: Number of positions being elected; Position title; Names of candidates; each block separated by one line break',
  `electionInfoAsEntered` text collate utf8_unicode_ci NOT NULL COMMENT 'Election info',
  `referendumThresholdPercent` int(2) default '10' COMMENT 'Percentage of voters who must cast a vote in a referendum for the referendum to be countable',
  `ballotStart` datetime NOT NULL COMMENT 'Start date/time of the ballot',
  `ballotEnd` datetime NOT NULL COMMENT 'End date/time of the ballot',
  `ballotViewable` datetime NOT NULL COMMENT 'Date/time when the cast votes can be viewed',
  `instanceCompleteTimestamp` datetime default NULL COMMENT 'Timestamp for when the instance (configuration and voters list) is complete',
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
EOF
${mysql} ${bobDbDatabase} < /tmp/instances.sql
rm /tmp/instances.sql

# Create database user privileges (which will create the user if it does not exist)
${mysql} -e "GRANT SELECT ON ${bobDbDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"
${mysql} -e "GRANT SELECT ON ${bobDbIngestDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"

# Define a sample ballot
electionId='test-13-14-testelection'
backquote='`'
cat > /tmp/sampleballot.sql << EOF

# Create a test instance
DELETE FROM instances WHERE id = '${electionId}' LIMIT 1;
INSERT INTO instances VALUES (
	'${electionId}', '/test/13-14/testelection/', '13-14', 'testelection', 'provider', 'test', 'Test election', NULL, NULL, NULL, '${voteAdmin}', '${voteAdmin}', '${sampleBallotUsername}', 'Candidate order has been automatically randomised', 'My organisation', NULL, NULL, 'Yes',
'1
President
BLAIR, Tony
LUCAS, Caroline
THATCHER, Margaret
',
'1
President
BLAIR, Tony
LUCAS, Caroline
THATCHER, Margaret
',
'10', NOW(), NOW() + INTERVAL 1 HOUR, NOW() + INTERVAL 1 HOUR, NOW()
);

# Create the votes table
DROP TABLE IF EXISTS ${backquote}${electionId}_votes${backquote};
CREATE TABLE IF NOT EXISTS ${backquote}${electionId}_votes${backquote} (token VARCHAR(32) COLLATE utf8_unicode_ci NOT NULL PRIMARY KEY, v1p1 TINYINT(4), v1p2 TINYINT(4), v1p3 TINYINT(4)) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;

# Create the voter table and insert one voter
DROP TABLE IF EXISTS ${backquote}${electionId}_voter${backquote};
CREATE TABLE IF NOT EXISTS ${backquote}${electionId}_voter${backquote} (username VARCHAR(16) COLLATE utf8_unicode_ci NOT NULL PRIMARY KEY, voted TINYINT(4) DEFAULT 0, forename VARCHAR(255) COLLATE utf8_unicode_ci, surname VARCHAR(255) COLLATE utf8_unicode_ci, unit VARCHAR(255) COLLATE utf8_unicode_ci) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;
INSERT INTO ${backquote}${electionId}_voter${backquote} VALUES ('${sampleBallotUsername}', 0, 'Forename', 'Surname', 'My college');

EOF

# Create the ballot
${mysql} ${bobDbDatabase} < /tmp/sampleballot.sql
rm /tmp/sampleballot.sql

