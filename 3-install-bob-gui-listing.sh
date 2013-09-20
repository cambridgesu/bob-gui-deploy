#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI listing component


# Add the BOB software (the native voting component, without any setup management)
if [ ! -d ${documentRoot}/bob-gui ] ; then
        cd "${documentRoot}"
        git clone https://github.com/cusu/bob-gui.git
fi

# Put the database password into the password file
echo -n "${bobDbListingPassword}" > "${documentRoot}"/bob-gui/listing/dbpass-listing

# Create database user privileges (which will create the users if they do not exist)
${mysql} -e "GRANT SELECT ON ${bobDbDatabase}.instances TO '${bobDbListingUsername}'@'localhost' IDENTIFIED BY '${bobDbListingPassword}';"

