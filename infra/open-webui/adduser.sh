#!/bin/bash

set -o pipefail

email="${1}"
password="${2}"
role="${3}"
if [[ -z "${email}" || -z "${password}" || ("${role}" != "admin" && "${role}" != "user") ]]; then
  echo "Usage: $(basename "${0}") [email] [password] [admin/user]"
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

if echo "SELECT email FROM user WHERE email = '${email}';" | sqlite3 "${SQLITE_DB}" | grep -q "${email}"; then
  echo "Error: Email [${email}] already exists"
  exit 1
fi

uuid=$(uuidgen)
# htpasswd -B 產 bcrypt(-C 10 成本),-n 印 stdout,-b 吃參數密碼,username 給空字串;tr 去行首冒號與換行,留純雜湊
hash=$(htpasswd -bnBC 10 "" "${password}" | tr -d ':\n')
username=$(echo "${email}" | awk -F'@' '{print $1}')
profileImage='/user.png'
apiKey="sk-$(uuidgen | tr -d '-')"
created=$(date +%s)
updated=$(date +%s)
lastActive=$(date +%s)

if ! echo "INSERT INTO user (id, name, email, role, profile_image_url, api_key, created_at, updated_at, last_active_at, settings, info, oauth_sub) VALUES
('${uuid}', '${username}', '${email}', '${role}', '${profileImage}', '${apiKey}', '${created}', '${updated}', '${lastActive}', NULL, NULL, NULL);" | sqlite3 "${SQLITE_DB}"; then
  echo "Error: Failed to create user [${email}]"
  exit 1
fi

if ! echo "INSERT INTO auth (id, email, password, active) VALUES
('${uuid}', '${email}', '${hash}', 1);" | sqlite3 "${SQLITE_DB}"; then
  echo "Error: Failed to create auth [${email}]"
  exit 1
fi

echo "Info: Successfully created user [${email}]"
