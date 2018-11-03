#!/bin/bash
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the base system (LAMP stack with SSL, Auth)


# Update system
apt-get update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove

# Basic system software
apt-get -y install mlocate man wget

# Ensure we have Git
apt-get -y install git-core

# NTP
apt-get -y install ntp
if ! grep -qF "${timeServer1}" /etc/ntp.conf ; then
	echo "server ${timeServer1}" >> /etc/ntp.conf
	echo "server ${timeServer2}" >> /etc/ntp.conf
	echo "server ${timeServer3}" >> /etc/ntp.conf
fi
service ntp restart

# Install Apache (2.4)
apt-get -y install apache2 apache2-dev

# Enable OpenSSL
sudo a2enmod ssl

# Install PHP (7.2)
apt-get -y install php libapache2-mod-php

# Install MySQL (5.7)
apt-get -y install mysql-server mysql-client php-mysql

# Check versions using:
# apache2 -v
# mysql -V
# php -v

# Secure MySQL, by setting the root password if no password is currently set; see: http://linuxtitbits.blogspot.co.uk/2011/01/checking-mysql-connection-status.html
set +e
mysql -u root --password='' -e ';' 2>/dev/null
dbstatus=`echo $?`
set -e
if [ $dbstatus -eq 0 ]; then
        mysqladmin -u root password "${mysqlRootPassword}"
fi

# Ensure MySQL as root requires auth; see: https://websiteforstudents.com/mysql-server-installed-without-password-for-root-on-ubuntu-17-10-18-04/
mysql -u root -p${mysqlRootPassword} -e "UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';"
mysql -u root -p${mysqlRootPassword} -e "FLUSH PRIVILEGES;"
sudo systemctl restart mysql.service

# Secure MySQL (other aspects); see: https://gist.github.com/Mins/4602864
apt-get -y install expect
# SECURE_MYSQL=$(expect -c "
# set timeout 10
# spawn mysql_secure_installation
# expect \"Enter current password for root (enter for none):\"
# send \"$mysqlRootPassword\r\"
# expect \"Change the root password?\"
# send \"n\r\"
# expect \"Remove anonymous users?\"
# send \"y\r\"
# expect \"Disallow root login remotely?\"
# send \"y\r\"
# expect \"Remove test database and access to it?\"
# send \"y\r\"
# expect \"Reload privilege tables now?\"
# send \"y\r\"
# expect eof
# ")
# echo "$SECURE_MYSQL"
sudo mysql_secure_installation

# Disable MySQL password expiry system; see: http://stackoverflow.com/a/41552022
mysql -u root -p${mysqlRootPassword} -e "SET GLOBAL default_password_lifetime = 0;"

# Create a database binding for convenience
mysql="mysql -u root -p${mysqlRootPassword} -h localhost"

# Define the Apache layout norms for the distribution
apacheConfDirectory=/etc/apache2
apacheVhostsConfigDirectory=/etc/apache2/sites-available
apacheLogFilesDirectory=/var/log/apache2
apacheVhostsRoot=/var/www
apacheUser=www-data
apacheGroup=www-data
apacheSslKeyDirectory=/etc/ssl/private
apacheSslCrtDirectory=/etc/ssl/certs

# Let's Encrypt (free SSL certs), which will create a cron job
# See: https://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu-14-04
# See: https://certbot.eff.org/docs/using.html
add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get -y install python-certbot-apache

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
	chainFile="${apacheSslCrtDirectory}/${domainName}.ca-bundle.crt"
	if [ ! -r "${chainFile}" ] ; then
		if [ ! -r "${sslCertificateChain}" ] ; then
			echo "ERROR: The setup SSL chain file is not present"
			exit 1
		fi
		cp -pr "${sslCertificateChain}" "${chainFile}"
	fi
	apacheSslCertificateChainDirective="SSLCertificateChainFile  ${chainFile}"
fi

# Add authentication support, either Raven or Basic Auth
# For Raven, see: https://raven.cam.ac.uk/project/apache/INSTALL
authModuleDirective=''
if [ "$ravenAuth" = true ] ; then
	
	# Load and enable the Ucam-webauth Apache module if required
	if [ ! -f /usr/lib/apache2/modules/mod_ucam_webauth.so ]; then
		wget -P /tmp/ https://github.com/cambridgeuniversity/mod_ucam_webauth/releases/download/v2.0.5/libapache2-mod-ucam-webauth_2.0.5apache24.ubuntu-16.04_amd64.deb
		dpkg -i /tmp/libapache2-mod-ucam-webauth*.deb
		rm /tmp/libapache2-mod-ucam-webauth*.deb
	fi
	
	# Install Raven public key if not already present
	if [ ! -r ${apacheConfDirectory}/webauth_keys/pubkey2 ]; then
		mkdir -p ${apacheConfDirectory}/webauth_keys/
		wget -P ${apacheConfDirectory}/webauth_keys/ https://raven.cam.ac.uk/project/keys/pubkey2
	fi
	
	# Generate a cookie key for Raven auth; see: http://www.howtogeek.com/howto/30184/
	randpw(){ < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-16};echo;}
	cookieKey=`randpw`
	
	# Define a directive to include the module in the Apache configuration
	authModuleDirective=$'\n# Raven\n'
	authModuleDirective+='AAKeyDir '"${apacheConfDirectory}/webauth_keys/"$'\n'
	authModuleDirective+='AACookieKey "'"${cookieKey}"$'"\n'
	authModuleDirective+='AAClockSkew 30'

	# Generate the auth config
	authConfig='AuthType Ucam-WebAuth
		AADescription "Online voting"
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

# Create a vhost for the website if it doesn't exist already
vhostFile="${apacheVhostsConfigDirectory}/${domainName}.conf"
installationRoot="${apacheVhostsRoot}/${domainName}"
if [ ! -r ${vhostFile} ]; then
	cat > ${vhostFile} << EOF
## Voting website

# General server configuration

# Lock down main server configuration
HostnameLookups Off
UseCanonicalName Off
ServerSignature Off
<Directory />
	Options -Indexes
	AllowOverride None
</Directory>

${authModuleDirective}

# SSL hardening; based on: https://mozilla.github.io/server-side-tls/ssl-config-generator/ in modern profile mode; confirmed accessible to Win7/IE9
SSLProtocol             all -SSLv3 -TLSv1 -TLSv1.1
SSLCipherSuite          ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256
SSLHonorCipherOrder     on

# Time zone
php_value date.timezone 'Europe/London'

# Lock down PHP environment
php_admin_value output_buffering 0
php_admin_value expose_php 0
php_admin_value file_uploads 0
php_admin_value auto_prepend_file none
php_admin_value auto_append_file none
#!# Should be able to reduce this when the BOB roll generation routine is rewritten
php_admin_value memory_limit 512M


# Voting website (HTTPS)
#Listen 443
<VirtualHost *:443>
	ServerAdmin ${administratorEmail}
	ServerName ${domainName}
	ServerAlias ${domainName/www./}
	DocumentRoot ${installationRoot}/bob-gui/public_html
	CustomLog /var/log/apache2/${domainName}_SSL-access_log combined
	ErrorLog /var/log/apache2/${domainName}_SSL-error_log
	
	# Enable PHP parsing
	AddType application/x-httpd-php .php
	
	# Prevent file listings
	DirectoryIndex index.html index.php
	
	# SSL
	SSLEngine on
	SSLCertificateFile       ${apacheSslCrtDirectory}/${domainName}.crt
	SSLCertificateKeyFile    ${apacheSslKeyDirectory}/${domainName}.key
	${apacheSslCertificateChainDirective}
	
	# Authentication
	<Location />
		${authConfig}
		Require valid-user
	</Location>

	# Logout page
	<Files logout.html>
		SetHandler AALogout
		AALogoutMsg /loggedout.html
	</Files>
	<Location /style/>
		Allow from all
		Satisfy Any
	</Location>
	
	# Load directives for BOB GUI control panel (may later be disabled at application level); NB Currently this must come before the listing directives
	Include ${installationRoot}/bob-gui/controlpanel/apache.conf
	#Use MacroVotingControlpanel "/controlpanel" "Managed voting system - control panel"
	<Location /controlpanel/>
		# Allow use of "Require user XXX YYY" in .htaccess file to limit access further
		AllowOverride AuthConfig
	</Location>
	
	# Remove fbclid=... from URLs; for now this will remove the full query string; see: https://stackoverflow.com/questions/52847475/what-is-fbclid-the-new-facebook-parameter
	RewriteEngine On
	RewriteCond %{QUERY_STRING} "fbclid="
	RewriteRule /(.*) /$1? [R=301,L]
	
	# Load directives for BOB GUI listing
	Include ${installationRoot}/bob-gui/listing/apache.conf
	
</VirtualHost>

# Voting website (HTTP)
<VirtualHost *:80>
	ServerAdmin ${administratorEmail}
	ServerName ${domainName}
	ServerAlias ${domainName/www./}
	DocumentRoot ${installationRoot}/bob-gui/public_html
	CustomLog /var/log/apache2/${domainName}-access_log combined
	ErrorLog /var/log/apache2/${domainName}-error_log
	
	# Redirect all traffic to the SSL vhost (at which point authentication will occur)
	Redirect permanent / https://${domainName}/
	
</VirtualHost>
EOF
fi

# Enable modules
a2enmod rewrite
a2enmod macro

# Enable the site and restart
a2ensite www.vote.cusu.cam.ac.uk

# Create a group for web editors, who can edit the files
if ! grep -i "^${webEditorsGroup}\b" /etc/group > /dev/null 2>&1 ; then
	groupadd "${webEditorsGroup}"
fi

# Add the current user to the web editors' group, if not already in it
currentActualUser=`who am i | awk '{print $1}'`
if ! groups ${currentActualUser} | grep "\b${webEditorsGroup}\b" > /dev/null 2>&1 ; then
	usermod -a -G "${webEditorsGroup}" "${currentActualUser}"
fi

# Create the document root and let the web group write to it
mkdir -p "${installationRoot}"
chown nobody."${webEditorsGroup}" "${installationRoot}"
chmod g+ws "${installationRoot}"
umask 0002

