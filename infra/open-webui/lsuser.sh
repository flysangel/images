#!/bin/bash

set -o pipefail

echo "Info: Table user"
echo "select email from user;" | sqlite3 "${SQLITE_DB}"
echo ""

echo "Info: Table auth"
echo "select email from auth;" | sqlite3 "${SQLITE_DB}"
