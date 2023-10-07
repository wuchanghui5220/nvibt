#!/bin/bash

for dev in $(sudo lspci | grep Mellanox | cut -d" " -f1)
    do
        echo -e "\n$dev $(sudo lspci -xxxvvv -s $dev | grep -E 'Name|SN|PN' |sed '/Product Name/s/^[[:space:]]*//'| sed 's/ *$//')"
    done
