#!/bin/bash
# Session 2 - Task 2: adduser vs useradd demo
# Run with: sudo bash user-demo.sh
# Each command's output is saved to ~/user-demo-logs/NN.txt (used for the README screenshots).

LOG=/home/${SUDO_USER:-$USER}/user-demo-logs
mkdir -p "$LOG"
n=0
run() {
  n=$((n + 1))
  echo "\$ $*"
  bash -c "$*" 2>&1 | tee "$LOG/$(printf %02d $n).txt"
}

# 1. adduser (recommended on Ubuntu) - interactive-friendly, creates home, copies /etc/skel, sets shell
run 'adduser --disabled-password --comment "DevOps Test User" devops-test'
run 'id devops-test'
run 'grep devops-test /etc/passwd'
run 'ls -la /home/devops-test'

# 2. useradd (low-level) - with no flags: no home directory, shell=/bin/sh, no password
run 'useradd devops-raw'
run 'grep devops-raw /etc/passwd'
run 'ls -ld /home/devops-raw'
run 'passwd -S devops-raw'

# 3. useradd needs flags to match what adduser does by default
run 'useradd -m -s /bin/bash -c "Raw user with flags" devops-raw2'
run 'grep devops-raw /etc/passwd; ls -ld /home/devops-raw2'

# cleanup the useradd demo users (keep devops-test as the test user created with adduser)
run 'userdel devops-raw; userdel -r devops-raw2; getent passwd devops-raw devops-raw2 || echo "useradd demo users removed"'

chown -R "${SUDO_USER:-$USER}:" "$LOG"
echo USER_DEMO_DONE
