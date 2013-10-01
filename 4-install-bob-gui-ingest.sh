#!/bin/bash
# Tested on SLES 12.0 with SDK installed
# This script is idempotent - it can be safely re-run without destroying existing data


# Installation of the GUI ingesting (config transfer) component


# Install prerequisites
zypper -n install -l php-openssl

# Create a user account which will do the ingesting
id -u bobguiIngest &>/dev/null || useradd bobguiIngest


