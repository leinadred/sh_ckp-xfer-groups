# Description

Script to transfer group object (including members, see [Caveats](#CAVEATS) )

Maybe a starting point for other ideas / scripts or something else

It started here <a href="https://community.checkpoint.com/t5/API-CLI-Discussion/Exporting-large-group-of-IPs-into-a-file-from-mgmt-cli/m-p/242611#M8950" target="_blank">Check Point Checkmates</a>

## Change Log

20250301 - added capability to work with Smart-1 Cloud instances

- set variable SOURCE_MAAS_TENANT or TARGET_MAAS_TENANT to your Smart-1 Tenant ID, otherwise let empty ("")
- capability to use api-keys: use "api-key" as username, script will then use the entered password as api-key
- added transferring color and comment attributes


# Usage

## "Import Mode"

Gets given group from source server and creates them on destination server - including member objects (hosts or networks

```shell
bash ./xfer-groups.sh <source-server_IP-or-FQDN> <source-server_USER> <source-server_PASSWORD> <group-name> [-i <destination-server_IP-or-FQDN> <source-server_USER> <source-server_PASSWORDN> ]
```

## "Export Mode"

Fetches given group and saves its member objects (in a csv file)

```shell
bash ./xfer-groups.sh <source-server_IP-or-FQDN> <source-server_USER> <source-server_PASSWORD> <group-name> 
```
exports member objects into csv files (separated through type (host/network)

# Caveats

- currently only ex- /importing host objects or network objects supported. no domains, no check point objects and so on
- currently only works with new to-create network objects/hosts. maybe will adjust that at a later moment.


in case somethin more breaks - feel free to debug or reach out at <a href="https://community.checkpoint.com/t5/user/viewprofilepage/user-id/1663" target="_blank">Nueueuel</a>
