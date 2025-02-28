#!/bin/bash

# Konfiguration (Konstanten)
SOURCE_SERVER_PORT="443"
TARGET_SERVER_PORT="443"
API_PATH="/web_api"

# Funktion zum Abrufen des SIDs
get_sid() {
  local server_url="$1" user="$2" password="$3"
  local payload="{\"user\":\"$user\", \"password\":\"$password\"}"
  curl --insecure "$server_url/login" -X POST -H "Content-Type: application/json" -d "$payload" | jq -r .sid
}

# Funktion zum Veröffentlichen der Änderungen
publish() {
  local sid="$1" server_url="$2"
  curl --insecure "$server_url/publish" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d '{}'
}

# Funktion zum Abrufen der Gruppeninformationen
get_group_data() {
  local sid="$1" groupname="$2" server_url="$3"
  curl --insecure -s "$server_url/show-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "{\"name\": \"$groupname\"}"
}

# Funktion zum Erstellen eines Gruppenobjekts
create_group_object() {
  local sid="$1" groupname="$2" comments="$3" server_url="$4"
  local payload="{\"name\":\"$groupname\", \"comments\":\"$comments\"}"
  curl --insecure "$server_url/add-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload"
  publish "$sid" "$server_url"
}

# Funktion zum Erstellen eines Netzwerkobjekts
create_network_object() {
  local sid="$1" groupid="$2" name="$3" subnet="$4" mask="$5" comments="$6" tags="$7" server_url="$8"
  local payload
  if [[ -z "$tags" ]]; then tags="[]"; fi
  payload="{\"name\":\"$name\", \"subnet4\":\"$subnet\", \""mask-length4"\":\"$mask\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"tags\":$tags}"
  curl --insecure "$server_url/add-network" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq .
}

# Funktion zum Erstellen eines Hostobjekts
create_host_object() {
  local sid="$1" groupid="$2" name="$3" ip="$4" comments="$5" tags="$6" server_url="$7"
  local payload
  if [[ -z "$tags" ]]; then tags="[]"; fi
  payload="{\"name\":\"$name\", \""ip-address"\":\"$ip\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"tags\":$tags}"
  curl --insecure "$server_url/add-host" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq .
}

# Argumentverarbeitung
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <source_server_ip_or_hostname> <source_user> <source_pass> <groupname> [-i <target_server_ip_or_hostname> <target_user> <target_pass>]"
  exit 1
fi

SOURCE_SERVER_IP_OR_HOSTNAME="$1" SOURCE_USERNAME="$2" SOURCE_PASSWORD="$3" GROUPNAME="$4"

if [[ "$5" == "-i" ]]; then # Importmodus
  if [[ $# -ne 8 ]]; then
    echo "Usage: $0 <source_server_ip_or_hostname> <source_user> <source_pass> <groupname> -i <target_server_ip_or_hostname> <target_user> <target_pass>"
    exit 1
  fi
  TARGET_SERVER_IP_OR_HOSTNAME="$6" TARGET_USERNAME="$7" TARGET_PASSWORD="$8"

  SOURCE_SERVER="https://${SOURCE_SERVER_IP_OR_HOSTNAME}:${SOURCE_SERVER_PORT}${API_PATH}"
  TARGET_SERVER="https://${TARGET_SERVER_IP_OR_HOSTNAME}:${TARGET_SERVER_PORT}${API_PATH}"

  source_sid=$(get_sid "$SOURCE_SERVER" "$SOURCE_USERNAME" "$SOURCE_PASSWORD")
  target_sid=$(get_sid "$TARGET_SERVER" "$TARGET_USERNAME" "$TARGET_PASSWORD")
  if [[ -z "$source_sid" || -z "$target_sid" ]]; then
    echo "Error: Failed to obtain SID(s)."
    exit 1
  fi

  group_data=$(get_group_data "$source_sid" "$GROUPNAME" "$SOURCE_SERVER")
  

  group_comments="DO NOT ALTER - AUTOMATICALLY ADDED" 
  # group_comments=$(echo "$group_data" | jq -r '.comments') 
  create_group_object "$target_sid" "$GROUPNAME" "$group_comments" "$TARGET_SERVER"

  members=$(echo "$group_data" | jq '.members')
  if [[ -n "$members" && "$members" != "null" ]]; then
    echo "Members: $members"
    echo "$members" | jq -c '.[]' | while read member; do
      type=$(echo "$member" | jq -r '.type')
      name=$(echo "$member" | jq -r '.name')
      subnet=$(echo "$member" | jq -r '.subnet4')
      mask=$(echo "$member" | jq -r '."mask-length4"')
      comments="DO NOT ALTER - AUTOMATICALLY ADDED" 
      #comments=$(echo "$member" | jq -r '.comments') # is null - or use comments="DO NOT ALTER - AUTOMATICALLY ADDED"
      tags=$(echo "$member" | jq -r '.tags')
      ip=$(echo "$member" | jq -r '."ip-address"')

      if [[ "$type" == "network" ]]; then
        create_network_object "$target_sid" "$GROUPNAME" "$name" "$subnet" "$mask" "$comments" "$tags" "$TARGET_SERVER"
      elif [[ "$type" == "host" ]]; then
        create_host_object "$target_sid" "$GROUPNAME" "$name" "$ip" "$comments" "$tags" "$TARGET_SERVER"
      fi
    done
  publish "$target_sid" "$TARGET_SERVER"
  else
    echo "Error: Members array is empty or null"
  fi
else # Exportmodus
  SOURCE_SERVER="https://${SOURCE_SERVER_IP_OR_HOSTNAME}:${SOURCE_SERVER_PORT}${API_PATH}"
  source_sid=$(get_sid "$SOURCE_SERVER" "$SOURCE_USERNAME" "$SOURCE_PASSWORD")
  if [[ -z "$source_sid" ]]; then
    echo "Error: Failed to obtain source SID."
    exit 1
  fi

  group_members=$(get_group_data "$source_sid" "$GROUPNAME" "$SOURCE_SERVER" | jq -r '.members[] | [.name, .subnet4, ."mask-length4", .comments, .tags] | @csv')

  if [[ -z "$group_members" ]]; then
    echo "Error: Failed to retrieve group members."
    exit 1
  fi

  echo "name,ip-address,comments,tags" > group_data.csv
  echo "$group_members" >> group_data.csv
  echo "Group data written to group_data.csv"
fi
