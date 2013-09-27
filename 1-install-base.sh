#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the base system (LAMP stack with SSL, Auth)


# Basic system software
zypper -n install -l findutils-locate man wget

# Ensure we have Git
zypper -n install -l git-core

# NTP
zypper -n install -l ntp
if ! grep -qF "${timeServer1}" /etc/ntp.conf ; then
	echo "server ${timeServer1}" >> /etc/ntp.conf
	echo "server ${timeServer2}" >> /etc/ntp.conf
	echo "server ${timeServer3}" >> /etc/ntp.conf
fi
/etc/init.d/ntp restart

# Install LAMP stack
zypper -n install -l apache2 apache2-devel mysql mysql-client php5 php5-suhosin php5-mbstring php5-mysql apache2-mod_php5
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

# Secure MySQL (other aspects); see: https://gist.github.com/Mins/4602864
zypper -n install -l expect
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$mysqlRootPassword\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"

# Create a database binding for convenience
mysql="mysql -u root -p${mysqlRootPassword} -h localhost"

# Define the Apache layout norms for the distribution
apacheConfDirectory=/etc/apache2
apacheVhostsConfigDirectory=/etc/apache2/vhosts.d
apacheDefaultDocumentRoot=/srv/www/htdocs
apacheLogFilesDirectory=/var/log/apache2
apacheVhostsRoot=/srv/www/vhosts
apacheModulesDirectory=/usr/lib64/apache2
apacheUser=wwwrun
apacheGroup=www
apacheSslKeyDirectory=/etc/apache2/ssl.key
apacheSslCrtDirectory=/etc/apache2/ssl.crt

# Create a null vhost if it doesn't exist already
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
if $ravenAuth ; then
	
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
	authModuleDirective+=$'LoadModule ucam_webauth_module /usr/lib64/apache2/mod_ucam_webauth.so\n'
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
documentRoot="${apacheVhostsRoot}/${domainName}"
if [ ! -r ${vhostFile} ]; then
	cat > ${vhostFile} << EOF
## Voting website

# Enable mod_rewrite
LoadModule rewrite_module /usr/lib64/apache2/mod_rewrite.so

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
	DocumentRoot ${documentRoot}/bob-gui
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
	
	# Prevent file listings
	DirectoryIndex index.html index.php
	
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

	# Allow .htaccess file usage and mod_rewrite directives
	<Directory />
		AllowOverride FileInfo
		# FollowSymLinks is needed to enable mod_rewrite
		Options FollowSymLinks
	</Directory>

</VirtualHost>

# Voting website (HTTP)
NameVirtualHost *:80
<VirtualHost *:80>
	ServerAdmin ${serverAdmin}
	ServerName ${domainName}
	DocumentRoot ${documentRoot}/bob-gui
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
	
	# Redirect all traffic to the SSL vhost (at which point authentication will occur)
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

# Restart the webserver to pick up the changes
sudo /etc/init.d/apache2 restart

