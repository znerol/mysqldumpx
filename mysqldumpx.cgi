#!/bin/bash

set -e

################################################################################
##### CONFIGURATION ############################################################
################################################################################

# Mandatory: Set MYSQLDUMPX to the full path to the mysqldumpx.sh script.
# MYSQLDUMPX=/some/path/to/mysqldumpx.sh
MYSQLDUMPX="./mysqldumpx.sh"

# Optionally specify the path to the configuration file. If not given, mysqldumpx
# script will look into the default locations.
# CONFIG="/some/path/to/mysqldumpx.conf"
CONFIG="./examples/d7_test.conf"

################################################################################
##### DO NOT CHANGE ANYTHING BEYOND THIS LINE ##################################
################################################################################

echo "Content-Type: text/plain"
echo

# Check if we can execute mysqldumpx.sh
if [ ! -x "$MYSQLDUMPX" ]; then
    exit 1
fi

# Execute main script in clean environment
exec -c "$MYSQLDUMPX" "$CONFIG"
