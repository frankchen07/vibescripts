#!/bin/bash

# Define the directory containing the .md files
# DIRECTORY="/Users/fronk/Documents/github/writing/posts"
DIRECTORY="/Users/fronk/Documents/github/writing/posts"

# # Check if the directory exists
# if [ ! -d "$DIRECTORY" ]; then
#   echo "Directory $DIRECTORY does not exist."
#   exit 1
# fi

# # Loop through all .md files in the directory
# for file in "$DIRECTORY"/*.md; do
#   # Check if the file exists
#   if [ -f "$file" ]; then
#     # Use sed to replace curly quotes and curly apostrophes
#     sed -i 's/“/\"/g; s/”/\"/g; s/’/'\''/g' "$file"
#     echo "Processed $file"
#   else
#     echo "No .md files found in $DIRECTORY"
#     exit 1
#   fi
# done

# echo "All files processed."

# Check if the directory exists
if [ ! -d "$DIRECTORY" ]; then
  echo "Directory $DIRECTORY does not exist."
  exit 1
fi

# Check if there are any .md files in the directory
shopt -s nullglob
md_files=("$DIRECTORY"/*.md)
shopt -u nullglob

if [ ${#md_files[@]} -eq 0 ]; then
  echo "No .md files found in $DIRECTORY"
  exit 1
fi

# Loop through all .md files in the directory
for file in "${md_files[@]}"; do
  # Use sed to replace curly quotes and curly apostrophes
  sed -i.bak 's/“/"/g; s/”/"/g; s/’/'\''/g' "$file" && rm "$file.bak"
  echo "Processed $file"
done

echo "All files processed."
