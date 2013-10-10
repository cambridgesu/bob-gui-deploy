#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI listing component


# Add the BOB-GUI software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob-gui ] ; then
        cd "${documentRoot}"
        git clone https://github.com/cusu/bob-gui.git
fi

# Install the house style if not already present; note that the "--strip 1" will remove the top-level directory in the .tgz
if [ ! -r "${documentRoot}"/bob-gui/style/header.html ] ; then
	if [ ! -r "${houseStylePackage}" ] ; then
		echo "ERROR: The house style package file specified in the deployment config is not present"
		exit 1
	fi
	tar -xvf "${houseStylePackage}" --strip 1 -C ${documentRoot}/bob-gui/style/
	if [ ! -r "${documentRoot}"/bob-gui/style/header.html ] || [ ! -r "${documentRoot}"/bob-gui/style/footer.html ] ; then
		echo "ERROR: The house style package does not include a header file"
		rm ${documentRoot}/bob-gui/style/*
		exit
	fi
	chown nobody."${webEditorsGroup}" "${documentRoot}"/bob-gui/style/
	chmod g+w "${documentRoot}"/bob-gui/style/
fi

# Add the favicon, if required
if [ "${faviconObtainFromUrl}" ] ; then
	faviconFile="${documentRoot}"/bob-gui/favicon.ico
	if [ ! -r "${faviconFile}" ]; then
		wget -O "${faviconFile}" "${faviconObtainFromUrl}"
		chown nobody."${webEditorsGroup}" "${faviconFile}"
		chmod g+w "${faviconFile}"
	fi
fi

# Create the listing bootstrap file; it is harmless to leave the template in place
if [ ! -e "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php ] ; then
	cp -p "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php.template "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php
fi

# Convert some settings from boolean to string true/false, so PHP receives native boolean; ternary operator as at: http://stackoverflow.com/a/3953712
controlPanelLinkDirectly=$( $controlPanelLinkDirectly && echo 'true' || echo 'false')
disableListWhoVoted=$( $disableListWhoVoted && echo 'true' || echo 'false')

# Add the database credentials to the BOB listing file (replace the lines matching on the left with the whole config string on the right)
#!# Inconsistent namings here would be good to clear up
#!# controlPanelLinkEnabled currently pastes in a PHP value; should instead determine whether the setting is a string or bool and do its own quoting here
sed -i \
-e "s/.*'username'.*/\$config['username'] = '${bobDbListingUsername}';/" \
-e "s/.*'password'.*/\$config['password'] = '${bobDbListingPassword}';/" \
-e "s/.*'administratorEmail'.*/\$config['administratorEmail'] = '${serverAdmin}';/" \
-e "s/.*'organisationName'.*/\$config['organisationName'] = '${organisationName}';/" \
-e "s/.*'mailDomain'.*/\$config['mailDomain'] = '${mtaUserMailDomain}';/" \
-e "s|.*'controlPanelUrl'.*|\$config['controlPanelUrl'] = '${controlPanelUrl}';|" \
-e "s/.*'controlPanelLinkEnabled'.*/\$config['controlPanelLinkEnabled'] = ${controlPanelLinkEnabled};/" \
-e "s/.*'controlPanelLinkDirectly'.*/\$config['controlPanelLinkDirectly'] = ${controlPanelLinkDirectly};/" \
	"${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php

# Add the database credentials and other fixed settings to the BOB bootstrap file (replace the lines matching on the left with the whole config string on the right)
sed -i \
-e "s/.*'dbDatabase'.*/\$config['dbDatabase'] = '${bobDbDatabase}';/" \
-e "s/.*'dbPassword'.*/\$config['dbPassword'] = '${bobDbPassword}';/" \
-e "s/.*'dbUsername'.*/\$config['dbUsername'] = '${bobDbUsername}';/" \
-e "s/.*'dbSetupUsername'.*/\$config['dbSetupUsername'] = '${bobDbSetupUsername}';/" \
-e "s/.*'disableListWhoVoted'.*/\$config['disableListWhoVoted'] = ${disableListWhoVoted};/" \
	"${documentRoot}"/bob-gui/bob/index.php

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

