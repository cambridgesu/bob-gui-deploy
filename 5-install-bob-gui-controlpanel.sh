#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI control panel component


# Enable the Apache configuration
directive="Include ${documentRoot}/bob-gui/controlpanel/apache.conf"
perl -p -i -e "s|#${directive}|${directive}|gi" "${vhostFile}"
sudo /etc/init.d/apache2 restart


