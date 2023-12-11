#!/bin/bash

# sudo chmod +x ./ibswinfo.sh

#ibswitches |head -1| awk -F'lid' '{print "lid"$2}' |awk '{print $1"-"$2}' | xargs -I {} ./ibswinfo.sh -d {}| grep -Ev "^-|^=" | awk -F'|' '{print $1}' |awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print}' | tr '\n' ',' > "$csv_file"

get_device_list() {
    ibswitches | awk -F'lid' '{print "lid"$2}' | awk '{print $1"-"$2}'
}

get_device_info() {
    ./ibswinfo.sh -d "$1" | grep -Ev "^-|^=" | awk -F'|' '{print $2}' | awk 'NR==1 {print} NR>1 {print}' | tr '\n' ',' | sed 's/,$/\n/'
}

main() {
    devices=$(get_device_list)

    for device in $devices; do
        info=$(get_device_info "$device")
        echo "$info"
        # echo "$info" >> "$csv_file"
    done
}

main
