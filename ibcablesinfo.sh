#!/bin/bash

mst restart &>/dev/null
mst cable add --with_ib  &>/dev/null

cables=$(mst status | awk '/Cables:/ {found=1; next} found {print $1}' |grep -v "^-")

echo "Wavelength,Vendor,Serial number,Part number,Temperature [c],Length [m]"

for cable in $cables; do
  mlxcables -d "$cable" -q \
          |grep -E "Wavelength|Vendor|Serial number|Part number|Temperature|Length" \
          |awk -F':' '{print $2}'\
          |sed 's/^[[:space:]]*//;s/[[:space:]]*$//'|tr '\n' ','
  echo ""
done
