#!/usr/bin/env bash
# Builds the HarbourDemo database from scratch on LocalDB. Override the server with SQL_SERVER=...
set -euo pipefail
cd "$(dirname "$0")"
SERVER="${SQL_SERVER:-(localdb)\\MSSQLLocalDB}"
start=$SECONDS
for f in 01-create-database.sql 02-schema.sql 03-generate-data.sql; do
    echo "== $f"
    sqlcmd -S "$SERVER" -E -b -I -i "$f"
done
echo "Setup finished in $((SECONDS - start)) seconds."
