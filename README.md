# Description

Script to transfer group object (including members, see [Caveats](#CAVEATS) )

Maybe a starting point for other ideas / scripts or something else

<a href="https://community.checkpoint.com/t5/API-CLI-Discussion/Exporting-large-group-of-IPs-into-a-file-from-mgmt-cli/m-p/242611#M8950" target="_blank">Check Point Checkmates!</a>


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
# Caveats

currently only ex- /importing host objects or network objects supported. no domains, no check point objects and so on
