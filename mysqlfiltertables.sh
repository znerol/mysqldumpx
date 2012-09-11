#!/usr/bin/env bash
# 
# Generate a list of tables in the specified MySQL database matching the given
# include and exclude patterns. The list of patterns is read from standard
# input, one pattern per line. Each line has the form:
#   include|exclude PATTERN
#
# Where PATTERN represents a MySQL LIKE pattern. Empty lines are ignored as
# well as lines starting with the comment character "#".
#
# Usage: mysqlfiltertables.sh [mysql options] database

# Terminate on error
set -e
set -o pipefail

# Fix path
export PATH=/bin:/usr/bin

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
