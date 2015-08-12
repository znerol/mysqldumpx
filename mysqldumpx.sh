#!/usr/bin/env bash

# Exit if some command returns with a non-zero status
set -e
set -o pipefail

# Fix path
export PATH=/bin:/usr/bin

# List of required commands
REQUIRED_COMMANDS="
    basename
    comm
    dirname
    echo
    grep
    gzip
    logger
    mktemp
    mysql
    mysqldump
    pwd
    rm
    sed
    sort
    tail
    test
    xargs
"

# Record datestamp
DATESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")

# Log message to stderr as well as syslog
log() {
    if [ -n "$DEBUG" ]; then
        logger -s -p user.notice -- "NOTE: $@"
    fi
}

# Log warning to stderr as well as syslog
warn() {
    logger -s -p user.info -- "WARNING: $@"
}

# Log error to stderr as well as syslog
err() {
    logger -s -p user.err -- "ERROR: $@"
}

# Generate a list of tables in the specified MySQL database matching the given
# include and exclude patterns. The list of patterns is read from standard
# input, one pattern per line. Each line has the form:
#   include|exclude PATTERN
#
# Where PATTERN represents a MySQL LIKE pattern. Empty lines are ignored as
# well as lines starting with the comment character "#".
#
# Usage: mysqlfiltertables.sh [mysql options] database
mysqlfiltertables() {(
    # Create temporary files
    INCLUDE_SQL=$(mktemp)
    EXCLUDE_SQL=$(mktemp)
    INCLUDE_TABLE=$(mktemp)
    EXCLUDE_TABLE=$(mktemp)
    trap "rm -f -- '$INCLUDE_TABLE' '$EXCLUDE_TABLE' '$INCLUDE_SQL' '$EXCLUDE_SQL'" EXIT

    # Read inclusion and exclusion patterns from stdin and construct SQL.
    sed -e "s/#.*//" -e "/^[[:space:]]*$/d" | while read action pattern; do
        case $action in
            include)
                echo "SHOW TABLES LIKE '$pattern';" >> "$INCLUDE_SQL"
                ;;
            exclude)
                echo "SHOW TABLES LIKE '$pattern';" >> "$EXCLUDE_SQL"
                ;;
        esac
    done

    # If no inclusion patterns were specified, start with all tables.
    if [ ! -s "$INCLUDE_SQL" ]; then
        echo "SHOW TABLES;" > "$INCLUDE_SQL"
    fi

    # Construct inclusion and exclusion table list by running the SQL.
    mysql "$@" --skip-column-names < "$INCLUDE_SQL" | sort > $INCLUDE_TABLE;
    mysql "$@" --skip-column-names < "$EXCLUDE_SQL" | sort > $EXCLUDE_TABLE;

    # Compare table sets and only report those entries which are in the inclusion
    # set but not in the exclusion set.
    comm -23 $INCLUDE_TABLE $EXCLUDE_TABLE;
)}

# Check if a config file can be sourced without side effects
checkconfig() {
    # Test if this file is accessible
    test -f "$1" -a -r "$1" || return 1

    # Strip comments and whitespace, after that verify that only variable
    # assignements are left.
    if sed -e "s/#.*//" -e "/^[[:space:]]*$/d" "$1" | \
        grep -qiv "^ *[a-z_][a-z0-9_]\{1,\}=[a-z_0-9\"'_ =/:\.+<>~-]*$"; then
        return 1
    fi
}

# Read a configuration file and run the commands. The function body is executed
# in a subshell in order to allow for changing directory, trapping and
# inheritance of variables.
runconfig() {(
    # Clear config variables which may not be inherited
    unset EXPAND
    unset DUMPFILE_ADD
    unset MYSQLDUMP_OPTS_ADD
    unset MYSQL_OPTS_ADD
    unset NAME

    # The following config variables are inheritable:
    # DATABASE
    # DUMPDIR
    # DUMPFILE
    # KEEP
    # MYSQLDUMP_OPTS
    # MYSQL_OPTS
    # TABLESET

    # Source configuration file
    source "$1"

    # Derive config-name from file name if necessary
    if [ -z "$NAME" ]; then
        NAME="$(basename "$1" .conf)"
    fi

    # Setup DUMPDIR, defaults to dirname of topmost config file
    DUMPDIR="${DUMPDIR:-$(cd "$(dirname "$1")" && pwd)}"

    # Construct basename
    DUMPFILE_ADD="${DUMPFILE_ADD:-$NAME}"
    if [ -n "$DUMPFILE" ]; then
        DUMPFILE="$DUMPFILE-$DUMPFILE_ADD"
    else
        DUMPFILE="$DUMPFILE_ADD"
    fi

    # Check whether or not compression is enabled
    if [ "$COMPRESSION" = "no" ]; then
        extension="sql"
    else
        extension="sql.gz"
    fi

    # Append additional mysql options if any
    if [ -n "$MYSQL_OPTS_ADD" ]; then
        MYSQL_OPTS="$MYSQL_OPTS $MYSQL_OPTS_ADD"
    fi
    if [ -n "$MYSQLDUMP_OPTS_ADD" ]; then
        MYSQLDUMP_OPTS="$MYSQLDUMP_OPTS $MYSQLDUMP_OPTS_ADD"
    fi

    # Change directory to the home of the current config file
    cd "$(dirname "$1")"

    if [ -n "$EXPAND" ]; then
        # Run the confset if this is not a simple config (recurse)
        log "Running confsets from $NAME"
        runconfigfiles $EXPAND
        log "Finish running confsets from $NAME"
    else
        log "Running config $NAME"
        # Take a backup using the current configuration
        if [ -z "DATABASE" ]; then
            warn "  Failed to run config $NAME. No database specified"
            return
        fi

        # Construct tableset
        tables=''
        if [ -n "$TABLESET" ]; then
            tables=$(mysqlfiltertables $MYSQL_OPTS "$DATABASE" < "$TABLESET")
            if [ -z "$tables" ]; then
                warn "  No tables in database '$DATABASE' match the rules given in tableset '$TABLESET'. Skipping."
                return
            fi
        fi

        # Write dumpfile
        dumpfile="$DUMPDIR/$DUMPFILE-$DATESTAMP.$extension"
        log "  Dumping to file '$dumpfile'"

        trap "rm -f -- '$dumpfile'" ERR
        if [ "$COMPRESSION" = "no" ]; then
            mysqldump $MYSQL_OPTS $MYSQLDUMP_OPTS "$DATABASE" $tables > "$dumpfile"
        else
            mysqldump $MYSQL_OPTS $MYSQLDUMP_OPTS "$DATABASE" $tables | gzip > "$dumpfile"
        fi

        # Setting permissions
        if [ "$CHMOD" != "no" ]; then
            chmod $CHMOD "$dumpfile"
        fi
        trap - ERR

        # Setting permissions
        if [ "$CHMOD" != "no" ]; then
            chmod $CHMOD "$dumpfile"
        fi
        trap - ERR

        # Rotate
        if [ "$KEEP" -gt "0" ]; then
            log "  Purging old dumps"
            purge "$DUMPDIR/$DUMPFILE-" "$extension" $KEEP
        fi
        log "  Finish running config $NAME"
    fi
)}

# Check and run the given configuration files
runconfigfiles() {
    for configfile in "$@"; do
        if checkconfig "$configfile"; then
            runconfig "$configfile"
        else
            warn "Skipping invalid configfile '$configfile'"
        fi
    done
}

# Remove old backup files
purge() {
    prefix="$1"
    suffix="$2"
    keep="$3"

    files=$(ls -t1 -- "$prefix"*"$suffix")
    numfiles=$(echo "$files" | wc -l)
    if [ "$numfiles" -gt "$keep" ]; then
        echo "$files" | tail -n"$(($keep-$numfiles))" | xargs -d "\n" rm -f --
    fi
}


while getopts cd opts; do
    case $opts in
        d) DEBUG='yes';;
        c) CHECKONLY='yes';;
        ?) exit 1;;
    esac
done

shift $(($OPTIND-1))

# Check for required binaries
if ! which $REQUIRED_COMMANDS > /dev/null; then
    err "One or more of the required shell commands does is not available in your system"
    err "Required commands: $REQUIRED_COMMANDS"
    exit 1
fi

if [ "$CHECKONLY" = "yes" ]; then
    exit
fi

if [ "$#" -gt 0 ]; then
    # Run configfiles given on the command line if any
    runconfigfiles "$@"
    log "Done"
    exit
else
    # Otherwise check standard locations
    for f in "./mysqldumpx.conf" "~/mysqldumpx.conf" "/etc/mysqldumpx.conf"; do
        if [ -r "$f" ]; then
            runconfigfiles "$f"
            log "Done"
            exit
        fi
    done
fi

# If no config file was given and none was found, inform the user
err "No configuration file found. Either give one on the command line"
err "or place it into one of the standard locations: ./mysqldumpx.conf"
err "(next to mysqldumpx.sh), ~/mysqldumpx.conf or /etc/mysqldumpx.conf"
exit 1
