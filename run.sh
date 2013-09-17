#!/bin/bash
# Script to install BOB and its delegated management GUI on Ubuntu
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data

# SLES SDK is required; basically:
# 1) Download the SDK DVD1 .iso to /tmp/
# 2) Run yast (as root), and go to Software -> Add-On Products, then add the local path



# Narrate
echo "# BOBGUI installation $(date)"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#     This script must be run as root." 1>&2
    exit 1
fi

# Bomb out if something goes wrong
set -e

# Get the script directory see: http://stackoverflow.com/a/246128/180733
# The second single line solution from that page is probably good enough as it is unlikely that this script itself will be symlinked.
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTDIRECTORY=$DIR

# Load the config file
configFile=./.config.sh
if [ ! -x ./${configFile} ]; then
    echo "# The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi

# Load the credentials
. ./${configFile}

# Logging
# Use an absolute path for the log file to be tolerant of the changing working directory in this script
setupLogFile=$SCRIPTDIRECTORY/log.txt
touch ${setupLogFile}
echo "#	BOBGUI installation in progress, follow log file with: tail -f ${setupLogFile}"
echo "#	BOBGUI installation $(date)" >> ${setupLogFile}

# Basic system software
zypper -n install -l findutils-locate man wget

# Ensure we have Git
zypper -n install -l git-core

# NTP
zypper -n install -l ntp
if ! grep -v -q "${timeServer1}" /etc/ntp.conf ; then
	echo "server ${timeServer1}" >> /etc/ntp.conf
	echo "server ${timeServer2}" >> /etc/ntp.conf
	echo "server ${timeServer3}" >> /etc/ntp.conf
fi
/etc/init.d/ntp restart

# Install LAMP stack
zypper -n install -l apache2 apache2-devel mysql mysql-client php5 php5-suhosin php5-mysql apache2-mod_php5
# Check versions using:
# /usr/sbin/httpd2 -v (2.2.21)
# /usr/bin/mysql -V (5.5.25)
# /usr/bin/php -v (5.3.8)

# Start services
#!# SUSE doesn't complain if they are already started, but ideally these should check first
/etc/init.d/apache2 start
/etc/init.d/mysql start
# Can check run levels 3 & 5 are started, with:
# sudo /sbin/chkconfig -a apache2
# sudo /sbin/chkconfig -a mysql

# Secure MySQL, by setting the root password if no password is currently set; see: http://linuxtitbits.blogspot.co.uk/2011/01/checking-mysql-connection-status.html
set +e
mysql -u root --password='' -e ';' 2>/dev/null
dbstatus=`echo $?`
set -e
if [ $dbstatus -eq 0 ]; then
        mysqladmin -u root password "${mysqlRootPassword}"
fi

# Define the Apache layout norms for the distribution
apacheVhostsConfigDirectory=/etc/apache2/vhosts.d
apacheDefaultDocumentRoot=/srv/www/htdocs
apacheLogFilesDirectory=/var/log/apache2
apacheVhostsRoot=/srv/www/vhosts
apacheModulesDirectory=/usr/lib64/apache2
apacheUser=wwwrun
apacheGroup=www
apacheSslKeyDirectory=/etc/apache2/ssl.key
apacheSslCrtDirectory=/etc/apache2/ssl.crt

# Create a null vhost if it doesn't exist already, and restart
nullVhostFile="${apacheVhostsConfigDirectory}/000-null-vhost.conf"
if [ ! -r ${nullVhostFile} ]; then
        cat > ${nullVhostFile} << EOF
# This is a null vhost which any unauthorised CNAMES fired at the machine will pick up
<VirtualHost *:80>
        ServerAdmin webmaster@example.com
        ServerName localhost
        DocumentRoot ${apacheDefaultDocumentRoot}
        CustomLog ${apacheLogFilesDirectory}/null-host.example.com-access_log combined
        ErrorLog ${apacheLogFilesDirectory}/null-host.example.com-error_log
        HostnameLookups Off
        UseCanonicalName Off
        ServerSignature Off
        <Directory ${apacheDefaultDocumentRoot}>
                Options -Indexes
                AllowOverride None
                Order allow,deny
                Allow from all
        </Directory>
</VirtualHost>
EOF
fi
sudo /etc/init.d/apache2 restart

# Copy in the SSL key and certificate files if not already present
# For testing, create a self-signed key without a password using:
#  openssl req -nodes -new -x509 -keyout vote.example.com.key -out vote.example.com.crt
if [ ! -r "${apacheSslKeyDirectory}/${domainName}.key" ] ; then
	if [ ! -r "${sslCertificateKey}" ] ; then
		echo "ERROR: The setup SSL key file is not present"
		exit 1
	fi
	cp -pr "${sslCertificateKey}" "${apacheSslKeyDirectory}/${domainName}.key"
fi
if [ ! -r "${apacheSslCrtDirectory}/${domainName}.crt" ] ; then
	if [ ! -r "${sslCertificateCrt}" ] ; then
		echo "ERROR: The setup SSL certificate file is not present"
		exit 1
	fi
	cp -pr "${sslCertificateCrt}" "${apacheSslCrtDirectory}/${domainName}.crt"
fi

# Also add support for an optional SSL chain file
apacheSslCertificateChainDirective=''
if [ "${sslCertificateChain}" ] ; then
	if [ ! -r "${apacheSslCrtDirectory}/${domainName}.chain.crt" ] ; then
		if [ ! -r "${sslCertificateChain}" ] ; then
			echo "ERROR: The setup SSL chain file is not present"
			exit 1
		fi
		cp -pr "${sslCertificateChain}" "${apacheSslCrtDirectory}/${domainName}.chain.crt"
	fi
	apacheSslCertificateChainDirective="SSLCertificateChainFile  ${apacheSslCrtDirectory}/${domainName}.chain.crt"
fi

# Add authentication support, either Raven or Basic Auth
# For Raven, see: https://raven.cam.ac.uk/project/apache/INSTALL
authModuleDirective=''
if [ "${ravenAuth}" == 'true' ] ; then
	
	# Compile the Ucam-webauth Apache module if required
	if [ ! -r ${apacheModulesDirectory}/mod_ucam_webauth.so ]; then
		latestUcamwebauthVersion='2.0.0'
		cd /tmp
		wget https://raven.cam.ac.uk/project/apache/files/mod_ucam_webauth-${latestUcamwebauthVersion}.tar.gz
		tar zxf mod_ucam_webauth-${latestUcamwebauthVersion}.tar.gz
		cd mod_ucam_webauth-${latestUcamwebauthVersion}/
		/usr/sbin/apxs2 -c -i -lcrypto mod_ucam_webauth.c
		cd /tmp
		rm -rf mod_ucam_webauth-${latestUcamwebauthVersion}/
		cd "${SCRIPTDIRECTORY}"
	fi
	
	# Define a directive to include the module in the Apache configuration
	authModuleDirective=$'\n# Raven\nLoadModule ucam_webauth_module /usr/lib64/apache2/mod_ucam_webauth.so'

	# Generate a cookie key for Raven auth; see: http://www.howtogeek.com/howto/30184/
	randpw(){ < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-16};echo;}
	cookieKey=`randpw`
	
	# Generate the auth config
	authConfig='AADescription "Online voting"
		AACookieKey "'"${cookieKey}"'"
		AuthType Ucam-WebAuth
		AAForceInteract On'
else
	# Create an auth file; users need to be added manually
	authFile="${apacheVhostsConfigDirectory}/${domainName}.htpasswd"
	if [ ! -r ${authFile} ]; then
		touch $authFile
		echo "Add users here by running:   sudo /usr/bin/htpasswd2 ${authFile} username" >> ${authFile}
	fi
	
	# Generate the auth config
	authConfig='AuthName "Online voting"
		AuthType Basic
		AuthUserFile "'"${authFile}"'"'
fi

# Create a vhost for the website if it doesn't exist already, and restart
vhostFile="${apacheVhostsConfigDirectory}/${domainName}.conf"
documentRoot="${apacheVhostsRoot}/${domainName}"
if [ ! -r ${vhostFile} ]; then
	cat > ${vhostFile} << EOF
## Voting website

# General server configuration
${authModuleDirective}

# Lock down PHP environment
php_admin_value output_buffering 0
php_admin_value expose_php 0
php_admin_value file_uploads 0


# Voting website (HTTPS)
Listen 443
NameVirtualHost *:443
<VirtualHost *:443>
	ServerAdmin ${serverAdmin}
	ServerName ${domainName}
	DocumentRoot ${documentRoot}
	CustomLog /var/log/apache2/${domainName}_SSL-access_log combined
	ErrorLog /var/log/apache2/${domainName}_SSL-error_log
	HostnameLookups Off
	UseCanonicalName Off
	ServerSignature Off
	<Directory />
		Options -Indexes
		AllowOverride None
		Order allow,deny
		Allow from all
	</Directory>
	
	# SSL
	SSLEngine on
	SSLCertificateFile       ${apacheSslCrtDirectory}/${domainName}.crt
	SSLCertificateKeyFile    ${apacheSslKeyDirectory}/${domainName}.key
	${apacheSslCertificateChainDirective}
	
	# Authentication
	<Directory />
		${authConfig}
		Require valid-user
	</Directory>
	<Files logout.html>
		SetHandler AALogout
	</Files>
	
	# Deny technical files being retrieved via a browser
	<Files ".ht*">
		deny from all
	</Files>
	<Files "dbpass">
		deny from all
	</Files>

</VirtualHost>

# Voting website (HTTP)
NameVirtualHost *:80
<VirtualHost *:80>
	ServerAdmin ${serverAdmin}
	ServerName ${domainName}
	DocumentRoot ${documentRoot}
	CustomLog /var/log/apache2/${domainName}-access_log combined
	ErrorLog /var/log/apache2/${domainName}-error_log
	HostnameLookups Off
	UseCanonicalName Off
	ServerSignature Off
	<Directory /srv/www/vhosts/${domainName}>
		Options -Indexes
		AllowOverride None
		Order allow,deny
		Allow from all
	</Directory>
	
	# Redirect all traffic to the SSL vhost
	Redirect permanent / https://${domainName}/
	
</VirtualHost>
EOF
fi

# Create a group for web editors, who can edit the files
if ! grep -i "^${webEditorsGroup}\b" /etc/group > /dev/null 2>&1 ; then
	groupadd "${webEditorsGroup}"
fi

# Add the current user to the web editors' group, if not already in it
currentActualUser=`who am i | awk '{print $1}'`
if ! groups ${currentActualUser} | grep "\b${webEditorsGroup}\b" > /dev/null 2>&1 ; then
	usermod -A "${webEditorsGroup}" "${currentActualUser}"
fi

# Create the document root and let the web group write to it
mkdir -p "${documentRoot}"
chown nobody."${webEditorsGroup}" "${documentRoot}"
chmod g+ws "${documentRoot}"
umask 0002

# Restart the webserver
sudo /etc/init.d/apache2 restart

# Add the BOB software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob ] ; then
	cd "${documentRoot}"
	git clone https://github.com/cusu/bob.git
fi

# Create a database binding
mysql="mysql -u root -p${mysqlRootPassword} -h localhost"

# Use the database version of the boostrap file rather than the manual bootstap file
if [ -r "${documentRoot}"/bob/index-dbconfig.php ]; then
	mv "${documentRoot}"/bob/index-dbconfig.php "${documentRoot}"/bob/index.php
fi

# Add the database credentials to the bootstrap file (replace the lines matching on the left with the whole config string on the right)
sed -i \
-e "s/.*'dbDatabase'.*/\$config['dbDatabase'] = '${bobDbDatabase}';/" \
-e "s/.*'dbUsername'.*/\$config['dbUsername'] = '${bobDbUsername}';/" \
-e "s/.*'dbSetupUsername'.*/\$config['dbSetupUsername'] = '${bobDbSetupUsername}';/" \
	"${documentRoot}"/bob/index.php

# Put the password into the password file
echo -n "${bobDbPassword}" > "${documentRoot}"/bob/dbpass

# Create the voting database
${mysql} -e "CREATE DATABASE IF NOT EXISTS ${bobDbDatabase} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create database user privileges (which will create the users if they do not exist); see: https://github.com/cusu/bob/blob/master/BOB.php#L1436
${mysql} -e "GRANT SELECT,INSERT,UPDATE ON ${bobDbDatabase}.* TO '${bobDbUsername}'@'localhost'      IDENTIFIED BY '${bobDbPassword}';"
${mysql} -e "GRANT SELECT,CREATE        ON ${bobDbDatabase}.* TO '${bobDbSetupUsername}'@'localhost' IDENTIFIED BY '${bobDbPassword}';"

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

# Add a sample ballot
cat > /tmp/sampleballot.sql << EOF

# Create the instance
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
${mysql} ${bobDbDatabase} < /tmp/sampleballot.sql
rm /tmp/sampleballot.sql

