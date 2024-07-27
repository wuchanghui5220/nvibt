#!/bin/bash

# Check if the input file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

input_file="$1"
output_file="${input_file%.*}.csv"

# Remove the first 14 lines, replace ":" with "," and output to CSV
sed '1,14d' "$input_file" | 
awk -F' *: *' '{
    for (i=1; i<=NF; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i);  # Trim leading/trailing whitespace
        if (i==NF) {
            printf "%s\n", $i;
        } else {
            printf "%s,", $i;
        }
    }
}' > "$output_file"

echo "Conversion complete. Output saved to $output_file"
