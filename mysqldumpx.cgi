#!/bin/bash

set -e

################################################################################
##### CONFIGURATION ############################################################
################################################################################

# Mandatory: Set MYBACKUP to the full path to the mybackup.sh script.
# MYBACKUP=/some/path/to/mybackup.sh
MYBACKUP="./mybackup.sh"

# Optionally specify the path to the configuration file. If not given, mybackup
# script will look into the default locations.
# CONFIG="/some/path/to/mybackup.conf"
CONFIG="./examples/d7_test.conf"

################################################################################
##### DO NOT CHANGE ANYTHING BEYOND THIS LINE ##################################
################################################################################

echo "Content-Type: text/plain"
echo

# Check if we can execute mybackup.sh
if [ ! -x "$MYBACKUP" ]; then
    exit 1
fi

# Execute main script in clean environment
exec -c "$MYBACKUP" "$CONFIG"
