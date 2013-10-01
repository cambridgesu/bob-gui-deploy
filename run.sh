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
cd "${SCRIPTDIRECTORY}"

# Load the config file
configFile=./.config.sh
if [ ! -x ./${configFile} ]; then
	echo "ERROR: The config file, ${configFile}, does not exist or is not excutable - copy your own based on the ${configFile}.template file." 1>&2
	exit 1
fi

# Ensure the config file has no placeholders left
if grep -qF "'?'" ./${configFile} ; then
	echo "ERROR: The config file, ${configFile}, still contains '?' placeholders." 1>&2
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


# Install the base system
source ./1-install-base.sh

# Install the voting component (BOB), if required
if $installBob ; then
	source ./2-install-bob.sh
fi

# Install the GUI listing component, if required
if $installBobGuiListing ; then
	source ./3-install-bob-gui-listing.sh
fi

# Install the GUI ingesting (config transfer) component, if required
if $installBobGuiIngest ; then
	source ./4-install-bob-gui-ingest.sh
fi

# Install the GUI control panel component, if required
if $installBobGuiControlpanel ; then
	source ./5-install-bob-gui-controlpanel.sh
fi


