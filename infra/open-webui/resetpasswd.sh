#!/bin/bash

set -o pipefail

email="${1}"
password="${2}"
if [[ -z "${email}" || -z "${password}" ]]; then
  echo "Usage: $(basename "${0}") [email] [password] "
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

if ! echo "SELECT COUNT(*) FROM user WHERE email='${email}';" | sqlite3 "${SQLITE_DB}" | grep -q "[^0]"; then
  echo "Error: Email [${email}] not found in the database"
  exit 1
fi

# htpasswd -B 產 bcrypt(-C 10 成本),-n 印 stdout,-b 吃參數密碼,username 給空字串;tr 去行首冒號與換行,留純雜湊
hash=$(htpasswd -bnBC 10 "" "${password}" | tr -d ':\n')
if ! echo "UPDATE auth SET password='${hash}' WHERE email='${email}';" | sqlite3 "${SQLITE_DB}"; then
  echo "Error: Failed to update password for user [${email}]"
  exit 1
fi

echo "Info: Successfully changed password for user [${email}]"
