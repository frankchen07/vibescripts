#!/bin/bash

# Check if input and output files are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 input.txt output.txt"
    exit 1
fi

input_file="$1"
output_file="$2"

# Use sed to process the file
sed -E '
    s/^(\t*)/\1- /;
    s/^-[[:space:]]([^\t])/- \1/;
    s/^-[[:space:]]*$//g;
    s/-[[:space:]]*###/\n---\n###/g;
    s/\n\n/\n/g;
    s/\n\n/\n/g
' "$input_file" > "$output_file"

echo "Processed $input_file and saved to $output_file."
