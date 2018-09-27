#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Define a sample ballot
electionId='test-15-16-testelection'
backquote='`'
cat > /tmp/sampleballot.sql << EOF

# Create a test instance
DELETE FROM instances WHERE id = '${electionId}' LIMIT 1;
INSERT INTO instances VALUES (
	'${electionId}', '/test/15-16/testelection/', '15-16', 'testelection', 'provider', 'test', 'Test election', NULL, NULL, NULL, '${emailTech}', '${emailTech}', '${sampleBallotUsername}', 'Candidate order has been automatically randomised', 'My organisation', NULL, NULL, 'Yes',
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

