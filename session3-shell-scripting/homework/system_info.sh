#!/bin/bash
# Session 03 - Shell Scripting Homework: System Information Script
# Author: Ankit Kumar

# ---- Variables: store data from commands ----
current_date=$(date)
host_name=$(hostname)
user_name=$(whoami)

echo "=============================================="
echo "        SYSTEM INFORMATION SCRIPT"
echo "=============================================="

# 1. Current date
echo "Current Date : $current_date"

# 2. Hostname
echo "Hostname     : $host_name"

# 3. Username
echo "Username     : $user_name"

# 4. Disk usage
echo
echo "---------------- Disk Usage ------------------"
df -h /

# 5. Running processes (top 5 by CPU)
echo
echo "------------- Running Processes --------------"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6

# 6. User input with read -p
echo
read -p "Enter your name: " name
read -p "Enter a directory name to create: " dir_name

echo "Hello $name, creating directory '$dir_name'..."

# 7. Create a directory using mkdir
mkdir -p "$dir_name"

# 8. Create a file using touch
report_file="$dir_name/process.log"
touch "$report_file"

# 9. Store running processes in the file using > output redirection
ps aux > "$report_file"

echo "Saved $(wc -l < "$report_file") lines of process info to $report_file"
echo "Directory contents:"
ls -l "$dir_name"
echo "=============================================="
echo "Done. Thanks, $name!"
