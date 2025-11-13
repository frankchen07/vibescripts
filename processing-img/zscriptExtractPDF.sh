#!/bin/bash

# Check if input argument (filename) is given
if [ -z "$1" ]; then
  echo "Usage: $0 input.pdf"
  exit 1
fi

input="$1"
output_prefix="page_"

# Get number of pages in PDF
num_pages=$(qpdf --show-npages "$input")

# Loop through pages and split
for ((i=1; i<=num_pages; i++))
do
  qpdf "$input" --pages . $i -- "${output_prefix}${i}.pdf"
done

echo "Split $input into $num_pages pages."
