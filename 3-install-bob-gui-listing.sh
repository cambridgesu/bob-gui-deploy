#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI listing component


# Add the BOB-GUI software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob-gui ] ; then
        cd "${documentRoot}"
        git clone https://github.com/cusu/bob-gui.git
fi

# Create the listing bootstrap file
if [ ! -e "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php ] ; then
	mv "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php.template "${documentRoot}"/bob-gui/listing/bobguiListingWrapper.php
fi

# Add the database credentials to the listing bootstrap file (replace the lines matching on the left with the whole config string on the right)
sed -i \
-e "s/.*'dbDatabase'.*/\$config['dbDatabase'] = '${bobDbDatabase}';/" \
-e "s/.*'dbUsername'.*/\$config['dbUsername'] = '${bobDbUsername}';/" \
-e "s/.*'dbSetupUsername'.*/\$config['dbSetupUsername'] = '${bobDbSetupUsername}';/" \
	"${documentRoot}"/bob-gui/bob/index.php

# Put the database password into the listing password file, based on the template
if [ ! -e "${documentRoot}"/bob-gui/listing/dbpass-listing ] ; then
	mv "${documentRoot}"/bob-gui/listing/dbpass-listing.template "${documentRoot}"/bob-gui/listing/dbpass-listing
fi
echo -n "${bobDbListingPassword}" > "${documentRoot}"/bob-gui/listing/dbpass-listing

# Create database user privileges (which will create the users if they do not exist)
${mysql} -e "GRANT SELECT ON ${bobDbDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"

# Set up the instances table
cat > /tmp/instances.sql << \EOF
CREATE TABLE IF NOT EXISTS `instances` (
  `id` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Generated globally-unique ID',
  `title` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Title of this ballot',
  `urlMoreInfo` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'URL for more info about the ballot',
  `afterVoteMessageHtml` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'An extra message, if any, which people will see when they have voted',
  `emailReturningOfficer` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Returning Officer / mailbox',
  `emailTech` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'E-mail address of Technical Administrator',
  `officialsUsernames` varchar(255) collate utf8_unicode_ci NOT NULL COMMENT 'Usernames of Returning Officer + Sysadmins',
  `randomisationInfo` enum('','Candidate order has been automatically randomised','Candidate order has been automatically alphabetised','Candidates have been entered by the Returning Officer in the order shown') collate utf8_unicode_ci default NULL COMMENT 'Candidate ordering/randomisation',
  `adminDuringElectionOK` int(1) default '0' COMMENT 'Whether the administrator can access admin pages during the election',
  `organisationName` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'Organisation name',
  `organisationUrl` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'Organisation URL',
  `organisationLogoUrl` varchar(255) collate utf8_unicode_ci default NULL COMMENT 'URL of organisation''s logo',
  `headerLocation` varchar(255) collate utf8_unicode_ci default '/style/prepended.html' COMMENT 'Header house style file',
  `footerLocation` varchar(255) collate utf8_unicode_ci default '/style/appended.html' COMMENT 'Footer house style file',
  `electionInfo` text collate utf8_unicode_ci NOT NULL COMMENT 'Election info: Number of positions being elected; Position title; Names of candidates; each block separated by one line break',
  `referendumThresholdPercent` int(3) default '10' COMMENT 'Percentage of voters who must cast a vote in a referendum for the referendum to be countable',
  `ballotStart` datetime NOT NULL COMMENT 'Start date/time of the ballot',
  `ballotEnd` datetime NOT NULL COMMENT 'End date/time of the ballot',
  `ballotViewable` datetime NOT NULL COMMENT 'Date/time when the cast votes can be viewed',
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
EOF
${mysql} ${bobDbDatabase} < /tmp/instances.sql
rm /tmp/instances.sql

# Define a sample ballot
cat > /tmp/sampleballot.sql << EOF

# Create a test instance
DELETE FROM instances WHERE id = 'testelection' LIMIT 1;
INSERT INTO instances VALUES (
	'testelection', 'Test election', NULL, NULL, '${serverAdmin}', '${serverAdmin}', '${sampleBallotUsername}', 'Candidate order has been automatically randomised', '0', 'My organisation', NULL, NULL, '', '',
'1
President
BLAIR, Tony
THATCHER, Margaret
', '10', '2013-09-01', '2013-09-02', '2013-09-02'
);

# Create the votes table
CREATE TABLE IF NOT EXISTS testelection_votes (token VARCHAR(32) collate utf8_unicode_ci NOT NULL PRIMARY KEY, v1p1 TINYINT(4), v1p2 TINYINT(4)) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;

# Create the voter table and insert one voter
CREATE TABLE IF NOT EXISTS testelection_voter (username VARCHAR(16) collate utf8_unicode_ci NOT NULL PRIMARY KEY, voted TINYINT(4) DEFAULT 0, forename VARCHAR(255) collate utf8_unicode_ci, surname VARCHAR(255) collate utf8_unicode_ci, unit VARCHAR(255) collate utf8_unicode_ci) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;
INSERT IGNORE INTO testelection_voter VALUES ('${sampleBallotUsername}', 0, 'Forename', 'Surname', 'My college');

EOF

# Create the ballot
${mysql} ${bobDbDatabase} < /tmp/sampleballot.sql
rm /tmp/sampleballot.sql

