#!/bin/bash
# =============================================================================
# CentOS-to-Debian Migration Toolkit: Final Analyze & Dump Script
# -----------------------------------------------------------------------------
# This script is intended to run on the CentOS machine. It performs the following:
#   1) Gathers information about installed packages, services, and network config.
#   2) Creates a backup archive EXCLUDING raw database directories (/var/lib/pgsql /var/lib/mysql).
#   3) Creates SQL dumps for PostgreSQL (using pg_dumpall) and/or MariaDB/MySQL (using mysqldump).
#   4) Transfers the resulting backup, report, and SQL dumps to the Debian server via SSH.
#
# IMPORTANT:
#   - Replace YOUR_DEBIAN_USER and YOUR_DEBIAN_IP with your actual user and IP on the Debian server.
#   - Ensure you have SSH access and correct privileges to transfer files.
# =============================================================================

# ----------------------
# Variables (Replace with your data)
# ----------------------
BACKUP_DIR="/backup"                                    # Local directory for storing backups/reports on CentOS
BACKUP_FILE="$BACKUP_DIR/centos_backup-$(date +%F).tar.gz"
REPORT_FILE="$BACKUP_DIR/migration_report.txt"

DEBIAN_USER="YOUR_DEBIAN_USER"    # <-- Replace with your Debian server user 
DEBIAN_IP="YOUR_DEBIAN_IP"        # <-- Replace with the IP of your Debian server 
DEBIAN_BACKUP_DIR="/backup"

PG_DUMP_FILE="$BACKUP_DIR/postgres_dump.sql"
MY_DUMP_FILE="$BACKUP_DIR/mysql_dump.sql"

echo "$(date '+%Y-%m-%d %H:%M:%S') === Migration analysis started ==="

# 1) Create local backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# 2) Analyze installed packages (rpm -qa) and save to report
echo "$(date '+%Y-%m-%d %H:%M:%S') Analyzing installed packages..."
rpm -qa > "$REPORT_FILE"

# 3) Analyze running services on CentOS
echo "$(date '+%Y-%m-%d %H:%M:%S') Analyzing running services..."
systemctl list-units --type=service --state=running >> "$REPORT_FILE"

# 4) Analyze disabled services
echo "$(date '+%Y-%m-%d %H:%M:%S') Analyzing disabled services..."
systemctl list-unit-files --state=disabled >> "$REPORT_FILE"

# 5) Analyze network config (IP, firewall, ifcfg files)
echo "$(date '+%Y-%m-%d %H:%M:%S') Analyzing network & firewall..."
ip a >> "$REPORT_FILE"
cat /etc/sysconfig/network-scripts/ifcfg-* >> "$REPORT_FILE" 2>/dev/null
firewall-cmd --list-all >> "$REPORT_FILE" 2>/dev/null || echo "firewalld not installed." >> "$REPORT_FILE"

# 6) Create backup archive, excluding raw DB directories
echo "$(date '+%Y-%m-%d %H:%M:%S') Creating backup archive (excluding DB data directories)..."
tar --exclude=/var/lib/pgsql \
    --exclude=/var/lib/mysql \
    -czf "$BACKUP_FILE" \
    /etc \
    /var/www \
    /home \
    /root \
    /opt

# 7) If PostgreSQL is installed, create a SQL dump
if grep -q "postgresql-server" "$REPORT_FILE"; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') Detected PostgreSQL. Dumping all databases..."
  sudo -u postgres pg_dumpall > "$PG_DUMP_FILE"
fi

# 8) If MariaDB or MySQL is installed, create a SQL dump
if grep -Eq "mariadb-server|mysql-server" "$REPORT_FILE"; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') Detected MariaDB/MySQL. Dumping all databases..."
  mysqldump --all-databases -u root > "$MY_DUMP_FILE"
fi

# 9) Transfer backup, report, and any SQL dumps to the Debian server
echo "$(date '+%Y-%m-%d %H:%M:%S') Transferring files to Debian ($DEBIAN_USER@$DEBIAN_IP)..."
scp "$BACKUP_FILE" "$REPORT_FILE" "$PG_DUMP_FILE" "$MY_DUMP_FILE" "$DEBIAN_USER"@"$DEBIAN_IP":"$DEBIAN_BACKUP_DIR"

if [ $? -eq 0 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') Files transferred successfully."
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: File transfer failed."
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') === Migration analysis completed successfully ==="
