#!/bin/bash

# Configuration
SOURCE_SERVER_PORT="443"
TARGET_SERVER_PORT="443"
API_PATH="/web_api"

# Function to get the SID
get_sid() {
  local server="$1" user="$2" password="$3"
  local payload="{\"user\":\"$user\", \"password\":\"$password\"}"
  curl --insecure "$server/login" -X POST -H "Content-Type: application/json" -d "$payload" | jq -r .sid
}

# Function to publish changes
publish() {
  local sid="$1" server="$2"
  curl --insecure "$server/publish" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d '{}'
}

# Function to get group data
get_group_data() {
  local sid="$1" groupname="$2" server="$3"
  curl --insecure -s "$server/show-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "{\"name\": \"$groupname\"}"
}

# Function to create a group object
create_group_object() {
  local sid="$1" groupname="$2" comments="$3" server="$4"
  local payload="{\"name\":\"$groupname\", \"comments\":\"$comments\"}"
  curl --insecure "$server/add-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload"
  publish "$sid" "$server"
}

# Function to create a network object
create_network_object() {
  local sid="$1" groupid="$2" name="$3" subnet="$4" mask="$5" comments="$6" tags="$7" server_url="$8"
  local payload
  if [[ -z "$tags" ]]; then tags="[]"; fi
  payload="{\"name\":\"$name\", \"subnet4\":\"$subnet\", \"mask-length4\":\"$mask\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"tags\":$tags}"
  curl --insecure "$server_url/add-network" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq .
}

# Function to create a host object
create_host_object() {
  local sid="$1" groupid="$2" name="$3" ip="$4" comments="$5" tags="$6" server_url="$7"
  local payload
  if [[ -z "$tags" ]]; then tags="[]"; fi
  payload="{\"name\":\"$name\", \"ip-address\":\"$ip\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"tags\":$tags}"
  curl --insecure "$server_url/add-host" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq .
}

# Argument parsing
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <source_server_ip_or_hostname> <source_user> <source_pass> <groupname> [-i <target_server_ip_or_hostname> <target_user> <target_pass>]"
  exit 1
fi

SOURCE_SERVER_IP_OR_HOSTNAME="$1" SOURCE_USERNAME="$2" SOURCE_PASSWORD="$3" GROUPNAME="$4"

if [[ "$5" == "-i" ]]; then # Import mode
  if [[ $# -ne 7 ]]; then
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
  group_comments=$(echo "$group_data" | jq -r '.comments')
  create_group_object "$target_sid" "$GROUPNAME" "$group_comments" "$TARGET_SERVER"

  members=$(echo "$group_data" | jq '.members')
  if [[ -n "$members" && "$members" != "null" ]]; then
    echo "Members: $members"
    echo "$members" | jq -c '.[]' | while read member; do
      type=$(echo "$member" | jq -r '.type')
      name=$(echo "$member" | jq -r '.name')
      subnet=$(echo "$member" | jq -r '.subnet4')
      mask=$(echo "$member" | jq -r '."mask-length4"')
      comments=$(echo "$member" | jq -r '.comments')
      tags=$(echo "$member" | jq -r '.tags')
      ip=$(echo "$member" | jq -r '.ip-address')

      if [[ "$type" == "network" ]]; then
        create_network_object "$target_sid" "$GROUPNAME" "$name" "$subnet" "$mask" "$comments" "$tags" "$TARGET_SERVER"
      elif [[ "$type" == "host" ]]; then
        create_host_object "$target_sid" "$GROUPNAME" "$name" "$ip" "$comments" "$tags" "$TARGET_SERVER"
      fi
    done
  else
    echo "Error: Members array is empty or null"
  fi
else # Export mode
  SOURCE_SERVER="https://${SOURCE_SERVER_IP_OR_HOSTNAME}:${SOURCE_SERVER_PORT}${API_PATH}"
  source_sid=$(get_sid "$SOURCE_SERVER" "$SOURCE_USERNAME" "$SOURCE_PASSWORD")
  if [[ -z "$source_sid" ]]; then
    echo "Error: Failed to obtain source SID."
    exit 1
  fi

  group_data=$(get_group_data "$source_sid" "$GROUPNAME" "$SOURCE_SERVER")
  members=$(echo "$group_data" | jq '.members')

  if [[ -n "$members" && "$members" != "null" ]]; then
    echo "Exporting group members..."

    # Create CSV files
    echo "name,subnet,mask-length,comments,tags" > group_data_networks_${GROUPNAME}.csv
    echo "name,ip-address,comments,tags" > group_data_hosts_${GROUPNAME}.csv

    # Iterate through members and write to CSV files
    echo "$members" | jq -c '.[]' | while read member; do
      type=$(echo "$member" | jq -r '.type')
      name=$(echo "$member" | jq -r '.name')
      comments=$(echo "$member" | jq -r '.comments')
      tags=$(echo "$member" | jq -r '.tags')

      if [[ "$type" == "network" ]]; then
        subnet=$(echo "$member" | jq -r '.subnet4')
        mask=$(echo "$member" | jq -r '."mask-length4"')
        echo "\"$name\",\"$subnet\",\"$mask\",\"$comments\",\"$tags\"" >> group_data_networks_${GROUPNAME}.csv
      elif [[ "$type" == "host" ]]; then
        ip=$(echo "$member" | jq -r '."ip-address"')
        echo "\"$name\",\"$ip\",\"$comments\",\"$tags\"" >> group_data_hosts_${GROUPNAME}.csv
      fi
    done

    echo "Group data written to group_data_networks_${GROUPNAME}.csv and group_data_hosts_${GROUPNAME}.csv"
  else
    echo "Error: Members array is empty or null"
  fi
fi
