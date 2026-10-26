#!/bin/bash

set -o pipefail

email="${1}"
if [[ -z "${email}" ]]; then
  echo "Usage: $(basename "${0}") [email]"
  exit 1
fi

if ! [[ "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Error: Invalid email format [${email}]"
  exit 1
fi

if [[ -z "${SQLITE_DB}" || ! -f "${SQLITE_DB}" ]]; then
  echo "Error: SQLITE_DB environment variable is not set or database file does not exist"
  exit 1
fi

# COUNT 回傳數字字串，只要含任一非 0 數字即代表使用者存在（任何正整數至少有一位非 0）
if ! echo "SELECT COUNT(*) FROM user WHERE email='${email}';" | sqlite3 "${SQLITE_DB}" | grep -q "[^0]"; then
  echo "Error: Email [${email}] not found in the database"
  exit 1
fi

if ! echo "delete from user where email='${email}';" | sqlite3 "${SQLITE_DB}"; then
  echo "Error: Failed to delete user [${email}]"
  exit 1
fi

if ! echo "delete from auth where email='${email}';" | sqlite3 "${SQLITE_DB}"; then
  echo "Error: Failed to delete auth [${email}]"
  exit 1
fi

echo "Info: Successfully deleted user [${email}]"
