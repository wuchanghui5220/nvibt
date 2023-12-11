#!/bin/bash

ibnetdiscover -p | sed 's/ HCA/_HCA/g' \
  | grep -v ??? \
  | grep -v "Quantum Mellanox Technologies" \
  | grep ^SW \
  | grep -v "Mellanox Technologies Aggregation Node" \
  | grep -v "Mellanox" \
  | awk '{printf "%-3s %-s %-3s  <-->  %-3s %-3s %-3s\n", "lid-"$2, $13, "["$3"]", "["$10"]", $15, "lid-"$9}' \
  | sed 's/_HCA-/ HCA-/g'
