#!/bin/bash
# Script to install BOB and its delegated management GUI on Ubuntu
# Tested on openSUSE 12.1
# This script is idempotent - it can be safely re-run without destroying existing data


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
zypper -n install -l findutils-locate pico man

# Ensure we have Git
zypper -n install -l git-core

# Install LAMP stack
zypper -n install -l apache2 mysql-community-server php5 php5-suhosin php5-mysql apache2-mod_php5
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
apacheUser=wwwrun
apacheGroup=www

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

# Create a vhost for the website if it doesn't exist already, and restart
vhostFile="${apacheVhostsConfigDirectory}/${domainName}.conf"
documentRoot="${apacheVhostsRoot}/${domainName}"
if [ ! -r ${vhostFile} ]; then
	cat > ${vhostFile} << EOF
# Voting website
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
</VirtualHost>
EOF
fi
sudo /etc/init.d/apache2 restart

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

# Add the BOB software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob ] ; then
	cd "${documentRoot}"
	git clone https://github.com/cusu/bob.git
fi

