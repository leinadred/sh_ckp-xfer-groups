#!/bin/bash

# Configuration
SOURCE_SERVER_PORT="443"
TARGET_SERVER_PORT="443"
API_PATH="/web_api"
SOURCE_MAAS_TENANT=""
TARGET_MAAS_TENANT=""

# Function to get the SID
get_sid() {
  local server="$1" user="$2" password="$3"
  if [[  $user == "api-key" ]]; then
    local payload="{\"api-key\":\"$password\"}"
  else
    local payload="{\"user\":\"$user\", \"password\":\"$password\"}"
  fi
  curl -sS --insecure "$server/login" -X POST -H "Content-Type: application/json" -d "$payload" | jq -r .sid
}

# Function to publish changes
publish() {
  local sid="$1" server="$2"
  curl -sS --insecure "$server/publish" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d '{}'
}

logout(){
  local sid="$1" server="$2"
  curl -sS --insecure "$server/logout" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d '{}'
}

# Function to get group data
get_group_data() {
  local sid="$1" groupname="$2" server="$3"
  curl -sS --insecure "$server/show-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "{\"name\": \"$groupname\"}"
}

get_member_metadata() {
  local server="$1" sid="$2" type="$3" name="$4"
  if [[ "$type" == "network" ]]; then
    curl -sS --insecure "$server/show-network" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "{\"name\":\"$name\"}"
  elif [[ "$type" == "host" ]]; then
    curl -sS --insecure "$server/show-host" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "{\"name\"\"$name\"}"
  fi
}

# Function to create a group object
create_group_object() {
  local sid="$1" groupname="$2" comments="$3" color="$4" server="$5"
  local payload="{\"name\":\"$groupname\", \"comments\":\"$comments\", \"color\":\"$color\"}"
  curl -sS --insecure "$server/add-group" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload"
  publish "$sid" "$server"
}

# Function to create a network object
create_network_object() {
  local sid="$1" groupid="$2" name="$3" subnet="$4" mask="$5" comments="$6" color="$7" server_url="$8"
  local payload
  payload="{\"name\":\"$name\", \"subnet4\":\"$subnet\", \"mask-length4\":\"$mask\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"color\":\"$color\"}"
  curl -sS --insecure "$server_url/add-network" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq .
}

# Function to create a host object
create_host_object() {
  local sid="$1" groupid="$2" name="$3" ip="$4" comments="$5" color="$6" server_url="$7"
  local payload="{\"name\":\"$name\", \"ip-address\":\"$ip\", \"groups\":\"$groupid\", \"comments\":\"$comments\", \"color\":\"$color\"}"
  curl -sS --insecure "$server_url/add-host" -X POST -H "Content-Type: application/json" -H "X-chkp-sid: $sid" -d "$payload" | jq . 
}

# Argument parsing
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <source_server_ip_or_hostname> <source_user> <source_pass> <groupname> [-i <target_server_ip_or_hostname> <target_user> <target_pass>]"
  exit 1
fi

SOURCE_SERVER_IP_OR_HOSTNAME="$1" SOURCE_USERNAME="$2" SOURCE_PASSWORD="$3" GROUPNAME="$4"

if [[ "$5" == "-i" ]]; then # Import mode
  if [[ $# -ne 8 ]]; then
    echo "Usage: $0 <source_server_ip_or_hostname> <source_user> <source_pass> <groupname> -i <target_server_ip_or_hostname> <target_user> <target_pass>"
    exit 1
  fi
  TARGET_SERVER_IP_OR_HOSTNAME="$6" TARGET_USERNAME="$7" TARGET_PASSWORD="$8"
  if [ "$SOURCE_MAAS_TENANT" = "" ]; then
    SOURCE_SERVER="https://${SOURCE_SERVER_IP_OR_HOSTNAME}:${SOURCE_SERVER_PORT}${API_PATH}"
  else
    SOURCE_SERVER="https://${SOURCE_SERVER_IP_OR_HOSTNAME}:${SOURCE_SERVER_PORT}/${SOURCE_MAAS_TENANT}${API_PATH}"
  fi

  if [ "$TARGET_MAAS_TENANT" = "" ]; then
    TARGET_SERVER="https://${TARGET_SERVER_IP_OR_HOSTNAME}:${TARGET_SERVER_PORT}${API_PATH}"
  else
    TARGET_SERVER="https://${TARGET_SERVER_IP_OR_HOSTNAME}:${TARGET_SERVER_PORT}/${TARGET_MAAS_TENANT}${API_PATH}"
  fi

  source_sid=$(get_sid "$SOURCE_SERVER" "$SOURCE_USERNAME" "$SOURCE_PASSWORD")
  target_sid=$(get_sid "$TARGET_SERVER" "$TARGET_USERNAME" "$TARGET_PASSWORD")
  if [[ -z "$source_sid" || -z "$target_sid" ]]; then
    echo "Error: Failed to obtain SID(s)."
    exit 1
  fi

  group_data=$(get_group_data "$source_sid" "$GROUPNAME" "$SOURCE_SERVER")
  group_comments=$(echo "$group_data" | jq -r '.comments')
  group_color=$(echo "$group_data" | jq -r '.color')
  create_group_object "$target_sid" "$GROUPNAME" "$group_comments" "$group_color" "$TARGET_SERVER"

  members=$(echo "$group_data" | jq '.members')
  if [[ -n "$members" && "$members" != "null" ]]; then
    echo "$members" | jq -c '.[]' | while read member; do
      type=$(echo "$member" | jq -r '.type')
      name=$(echo "$member" | jq -r '.name')
      subnet=$(echo "$member" | jq -r '.subnet4')
      mask=$(echo "$member" | jq -r '."mask-length4"')
      ip=$(echo "$member" | jq -r '."ipv4-address"')
      metadata=$(get_member_metadata "$SOURCE_SERVER" "$source_sid" "$type" "$name")
      comments=$(echo "$metadata" | jq -r '.comments')
      color=$(echo "$metadata" | jq -r '.color')
      if [[ "$type" == "network" ]]; then
        create_network_object "$target_sid" "$GROUPNAME" "$name" "$subnet" "$mask" "$comments" "$color" "$TARGET_SERVER"
      elif [[ "$type" == "host" ]]; then
        create_host_object "$target_sid" "$GROUPNAME" "$name" "$ip" "$comments" "$color" "$TARGET_SERVER"
      fi
    done
  else
    echo "Error: Members array is empty or null"
  fi
  publish "$target_sid" "$TARGET_SERVER"
  echo "OK, Transfer has been made - logging out of sessions"
  logout "$source_sid" "$SOURCE_SERVER"
  logout "$target_sid" "$TARGET_SERVER"

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
    echo "name,subnet,mask-length,comments,color" > group_data_networks_${GROUPNAME}.csv
    echo "name,ip-address,comments,tags" > group_data_hosts_${GROUPNAME}.csv

    # Iterate through members and write to CSV files
    echo "$members" | jq -c '.[]' | while read member; do
      metadata=$(get_member_metadata "$SOURCE_SERVER" "$source_sid" "$type" "$name")
      type=$(echo "$member" | jq -r '.type')
      name=$(echo "$member" | jq -r '.name')
      comments=$(echo "$metadata" | jq -r '.comments')
      color=$(echo "$metadata" | jq -r '.color')
      if [[ "$type" == "network" ]]; then
        subnet=$(echo "$member" | jq -r '.subnet4')
        mask=$(echo "$member" | jq -r '."mask-length4"')
        echo "\"$name\",\"$subnet\",\"$mask\",\"$comments\",\"$color\"" >> group_data_networks_${GROUPNAME}.csv
      elif [[ "$type" == "host" ]]; then
        ip=$(echo "$member" | jq -r '."ipv4-address"')
        echo "\"$name\",\"$ip\",\"$comments\",\"$color\"" >> group_data_hosts_${GROUPNAME}.csv
      fi
    done

    echo "Group data written to group_data_networks_${GROUPNAME}.csv and group_data_hosts_${GROUPNAME}.csv"
  else
    echo "Error: Members array is empty or null"
  fi
fi
