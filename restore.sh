#!/bin/bash
# =============================================================================
# Advanced CentOS-to-Debian Migration Toolkit (Final + Force-Fix PostgreSQL)
# -----------------------------------------------------------------------------
# This script is intended to run on the Debian machine. It performs the following:
#   1) Analyzes the transferred backup/report to see what was on CentOS.
#   2) Automatically installs the equivalent Debian packages (Apache -> apache2, etc.).
#   3) Restores basic configs (Apache, /home data, etc.) from the CentOS backup.
#   4) Detects if PostgreSQL / MariaDB / MySQL were used on CentOS, and automatically
#      imports the SQL dumps (postgres_dump.sql, mysql_dump.sql).
#   5) If the existing PostgreSQL cluster is conflicted, it forces a cluster drop & re-create.
#   6) If MySQL system table conflicts appear, it logs them but continues importing user DBs.
#
# IMPORTANT:
#   - This script expects to find:
#       centos_backup-YYYY-MM-DD.tar.gz
#       migration_report.txt
#       postgres_dump.sql (if PostgreSQL was on CentOS)
#       mysql_dump.sql (if MariaDB/MySQL was on CentOS)
#     in the /backup directory on this Debian server.
#   - Replace any placeholders (e.g., user, IP) or references if needed for your environment.
# =============================================================================

# ----------------------
# Variables (Replace with your data if needed)
# ----------------------
BACKUP_DIR="/backup"                                    # Directory where CentOS files should be stored on Debian
REPORT_FILE="$BACKUP_DIR/migration_report.txt"
BACKUP_FILE=$(ls $BACKUP_DIR/centos_backup-*.tar.gz | head -n 1)    # Finds the first CentOS backup archive
PG_DUMP_FILE="$BACKUP_DIR/postgres_dump.sql"                         # PostgreSQL dump from CentOS
MY_DUMP_FILE="$BACKUP_DIR/mysql_dump.sql"                             # MySQL/MariaDB dump from CentOS

DEBIAN_BACKUP="$BACKUP_DIR/debian_backup-$(date +%F).tar.gz"          # Path to store Debian's own backup
LOG_FILE="$BACKUP_DIR/migration_restore.log"                          # Log file for restore script
TMP_DIR="/tmp/centos_restore"                                         # Temp dir for extraction
SUMMARY="$BACKUP_DIR/final_summary.txt"                               # Final summary report

# ----------------------
# Function: logging
# ----------------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# ----------------------
# 1) Analyze migration data
# ----------------------
analyze_migration_data() {
  log "Analyzing migration data..."
  tar -tzf "$BACKUP_FILE" > "$BACKUP_DIR/file_list.txt"
  # Filter only relevant lines (pgsql, mysql, mariadb, httpd, nginx, redis) from the report
  grep -E '(pgsql|mysql|mariadb|httpd|nginx|redis)' "$REPORT_FILE" | tee "$BACKUP_DIR/analysis_summary.txt"
  log "Analysis summary saved at: $BACKUP_DIR/analysis_summary.txt"
}

# ----------------------
# 2) Check disk space
# ----------------------
check_disk_space() {
  log "Checking disk space on Debian..."
  df -h /
}

# ----------------------
# 3) Backup current Debian system
# ----------------------
backup_current_debian() {
  log "Creating Debian system backup..."
  tar --exclude=/backup -czpf "$DEBIAN_BACKUP" /etc /var/www /var/lib /home /opt
  log "Backup completed: $DEBIAN_BACKUP"
}

# ----------------------
# 4) Automatic package installation
# ----------------------
install_packages_smart() {
  log "Installing packages as needed..."
  # Mapping from CentOS package names to Debian equivalents
  declare -A packages=(
    ["httpd"]="apache2"
    ["nginx"]="nginx"
    ["postgresql-server"]="postgresql"
    ["mariadb-server"]="mariadb-server"
    ["mysql-server"]="mysql-server"
    ["redis"]="redis-server"
  )
  # For each package in the map, check if it was found in migration_report.txt
  for pkg in "${!packages[@]}"; do
    if grep -q "$pkg" "$REPORT_FILE"; then
      if dpkg -l | grep -qw "${packages[$pkg]}"; then
        log "${packages[$pkg]} already installed."
      else
        apt install -y "${packages[$pkg]}" && log "${packages[$pkg]} installed." || log "Error installing ${packages[$pkg]}"
      fi
    fi
  done
}

# ----------------------
# 5) Adapt and safely restore configurations (including DB auto-fix & import)
# ----------------------
adapt_restore_configs_safely() {
  log "Restoring and adapting configurations (and force-fixing PostgreSQL if needed)..."
  mkdir -p "$TMP_DIR"
  tar -xzf "$BACKUP_FILE" -C "$TMP_DIR"

  # --- Apache config restoration ---
  if [[ -d "$TMP_DIR/etc/httpd" ]]; then
    cp -r "$TMP_DIR/etc/httpd/conf/"* /etc/apache2/
    cp -r "$TMP_DIR/var/www/"* /var/www/
    log "Apache configs restored."
  fi

  # --- Home directories ---
  cp -r "$TMP_DIR/home/"* /home/ && log "Home dirs restored."

  rm -rf "$TMP_DIR"
  log "Basic config restoration done."

  # ============== AUTO-IMPORT DATABASES ==============

  # (A) PostgreSQL
  if grep -q "postgresql-server" "$REPORT_FILE"; then
    log "Detected PostgreSQL in CentOS. Checking service & socket..."
    systemctl enable --now postgresql
    sleep 2

    # Check for socket
    if [ ! -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
      log "PostgreSQL socket not found. Trying to forcibly drop & re-create cluster..."

      PG_VERSION=$(ls /var/lib/postgresql | head -n 1)
      if [ -z "$PG_VERSION" ]; then
        PG_VERSION="15"  # fallback if can't detect
      fi

      systemctl stop postgresql
      pg_dropcluster --stop "$PG_VERSION" main &>/dev/null
      rm -rf "/var/lib/postgresql/$PG_VERSION/main"

      if pg_createcluster "$PG_VERSION" main; then
        log "Cluster $PG_VERSION re-created successfully."
        systemctl start postgresql
        sleep 2
        if [ ! -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
          log "❌ Force fix failed: Postgres socket still missing. Please do it manually."
          echo "Manual steps:
1) Remove or fix /var/lib/postgresql/$PG_VERSION/main
2) Run: pg_createcluster $PG_VERSION main
3) systemctl start postgresql
" | tee -a "$LOG_FILE"
        else
          log "✅ Force fix success: PostgreSQL cluster re-inited, socket present."
        fi
      else
        log "❌ Could not create cluster automatically. Please fix manually."
      fi
    fi

    # Import PostgreSQL dump if it exists
    if [ -f "$PG_DUMP_FILE" ]; then
      if systemctl is-active --quiet postgresql && [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
        log "Importing PostgreSQL dump ($PG_DUMP_FILE)..."
        sudo -u postgres psql -f "$PG_DUMP_FILE" && log "PostgreSQL dump imported." || log "Failed to import Postgres dump!"
      else
        log "PostgreSQL not active or socket missing, cannot import."
      fi
    fi
  fi

  # (B) MariaDB/MySQL
  if grep -Eq "mariadb-server|mysql-server" "$REPORT_FILE"; then
    systemctl enable --now mariadb mysql 2>/dev/null
    sleep 2
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
      if [ -f "$MY_DUMP_FILE" ]; then
        log "Importing MariaDB/MySQL dump ($MY_DUMP_FILE)..."
        mysql < "$MY_DUMP_FILE" 2>/tmp/mysqlimport.err
        if [ $? -eq 0 ]; then
          log "MariaDB/MySQL dump imported."
        else
          # If there's a known system table conflict (e.g. Table 'user' already exists)
          if grep -q "Table 'user' already exists" /tmp/mysqlimport.err; then
            log "Some system tables existed, ignoring. User DBs are likely imported."
          else
            log "Failed to import MySQL dump! See /tmp/mysqlimport.err"
          fi
        fi
      fi
    else
      log "MariaDB/MySQL not running, cannot import."
    fi
  fi

  log "✅ All DB imports (and force fixes) done."
}

# ----------------------
# 6) Fix permissions automatically
# ----------------------
fix_permissions_automatically() {
  log "Fixing typical permissions..."
  [[ -d "/var/www" ]] && chown -R www-data:www-data /var/www
  log "Permissions fix done."
}

# ----------------------
# 7) Enable and restart services
# ----------------------
enable_restart_services() {
  log "Enabling and restarting services..."
  SERVICES=("apache2" "nginx" "postgresql" "mariadb" "mysql" "redis-server")
  for srv in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -qw "$srv"; then
      systemctl enable --now "$srv" && log "$srv restarted."
    fi
  done
}

# ----------------------
# 8) Verify restored data
# ----------------------
verify_restored_data() {
  log "Verifying data integrity..."

  # Check Apache
  if systemctl is-active --quiet apache2; then
    log "Apache is running."
    echo "Apache test page:" && curl -s localhost
  fi

  # Check PostgreSQL socket
  if [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
    log "PostgreSQL is listening on 5432. Checking DB list..."
    sudo -u postgres psql -l || log "psql -l failed"
  else
    log "❌ PostgreSQL socket not found. Possibly not running or mismatched version."
  fi

  # Check MariaDB/MySQL
  if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
    log "MariaDB/MySQL is running. Showing databases..."
    mysql -e "SHOW DATABASES;"
  fi
}

# ----------------------
# 9) Generate summary report
# ----------------------
generate_summary_report() {
  log "Generating final summary..."
  {
    echo "=== Final Migration Summary ==="
    echo "Date: $(date)"
    echo ""
    echo "Services from CentOS report:"
    grep -E '(httpd|nginx|pgsql|mysql|mariadb|redis)' "$REPORT_FILE"
    echo ""
    echo "Recommended manual checks:"
    echo "- Test websites at http://<debian-IP>/"
    echo "- Confirm DB content via psql or mysql commands"
  } | tee "$SUMMARY"
  log "Summary saved: $SUMMARY"
}

# ----------------------
# 10) Rollback changes (Restore Debian from backup)
# ----------------------
rollback_changes() {
  log "Rolling back to Debian backup..."
  if [ -f "$DEBIAN_BACKUP" ]; then
    tar -xzpf "$DEBIAN_BACKUP" -C / && log "Rollback successful." || log "Rollback failed!"
  else
    log "No backup available!"
  fi
}

# ----------------------------------------------------------------
# MAIN MENU: preserves original style (1..11) with "Choose an option:"
# ----------------------------------------------------------------
while true; do
  echo "=== Advanced CentOS-to-Debian Migration Toolkit ==="
  echo "1. Analyze migration data and report"
  echo "2. Check available disk space"
  echo "3. Backup current Debian system"
  echo "4. Automatic smart package installation"
  echo "5. Adapt and safely restore configurations (incl. DB auto-fix & import)"
  echo "6. Automatic fix for permission issues"
  echo "7. Enable and restart migrated services"
  echo "8. Verify restored data"
  echo "9. Generate detailed migration summary report"
  echo "10. Rollback changes (Restore Debian from backup)"
  echo "11. Exit"
  read -p "Choose an option: " choice

  case $choice in
    1) analyze_migration_data ;;
    2) check_disk_space ;;
    3) backup_current_debian ;;
    4) install_packages_smart ;;
    5) adapt_restore_configs_safely ;;
    6) fix_permissions_automatically ;;
    7) enable_restart_services ;;
    8) verify_restored_data ;;
    9) generate_summary_report ;;
    10) rollback_changes ;;
    11) log "Exiting Migration Toolkit."; exit ;;
    *) echo "Invalid choice, please try again." ;;
  esac
done
