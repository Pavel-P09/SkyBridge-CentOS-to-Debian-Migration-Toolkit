## CentOS-to-Debian Migration Toolkit

A comprehensive toolkit to **migrate** servers from **CentOS** to **Debian** in an **automated** and **safe** manner.

This solution provides:

- **Configuration Analysis** on CentOS (`analyze.sh`), including package detection, service listing, and network/firewall details.
- **Smart Backup** of CentOS data (excluding raw database files) and creation of **SQL dumps** for PostgreSQL and MariaDB/MySQL.
- **Automated Transfer** of the backup, report, and SQL dumps to the Debian server via SSH.
- **Automatic Restoration** on Debian (`restore.sh`), installing the equivalent packages, restoring configurations, adapting paths (e.g., `/etc/httpd` to `/etc/apache2`), and importing SQL dumps.
- **Force-Fix** of PostgreSQL if conflicts arise, plus handling of MySQL system table conflicts.

---

## Key Features

1. **Comprehensive Analysis**  
   Gathers info on packages, running/disabled services, network settings on CentOS.

2. **Backup Without Raw DB Files**  
   Excludes `/var/lib/pgsql` or `/var/lib/mysql` from the archive; uses `pg_dumpall` / `mysqldump` for safer DB migration.

3. **Automated Scripts**  
   - `analyze.sh` (on CentOS) creates a `.tar.gz` backup, a `migration_report.txt`, and SQL dumps if DB servers are detected.
   - `restore.sh` (on Debian) installs needed packages automatically, adapts configs, and imports the SQL dumps.

4. **Conflict Resolution**  
   Automatically drops & re-creates a broken PostgreSQL cluster, continues importing if MySQL system tables already exist, etc.

5. **Interactive Menu on Debian**  
   Each step is chosen via a numeric menu (analysis, installing packages, restoration, verification, summary, rollback).

---

## Supported Systems

- **CentOS Versions**  
  CentOS 7 or later (relies on `systemctl`, `firewall-cmd`, `rpm -qa`, etc.)

- **Debian Versions**  
  Debian 10, 11, or 12 tested (relies on `apt`, `systemctl`, etc.)

Recommended to match or exceed DB versions on Debian for smoother migration.

---

## Advantages

- **Minimizes Downtime**  
  Prepares data on CentOS, quickly restores to Debian.
- **Automatic DB Migration**  
  Uses logical dumps to avoid raw file copying.
- **Force-Fix for Common Issues**  
  Auto-fixes leftover PostgreSQL clusters, MySQL system table conflicts.
- **Detailed Logs & Reports**  
  Each script logs operations; `restore.sh` generates a final summary.

---

## Prerequisites

1. **Root or Sudo Access** on both CentOS and Debian  
2. **SSH Connectivity**  
   Required for file transfer. Optionally configure key-based auth.
3. **Sufficient Disk Space**  
   On CentOS: enough for creating a backup archive  
   On Debian: enough to receive/restore that backup

---

## Step-by-Step Guide

### 1. Initial SSH Setup (CentOS → Debian)

#### 1.1 Install SSH (if not installed)

**On CentOS**:
```bash
sudo yum install -y openssh-server
```
```bash
sudo systemctl enable --now sshd
```

**On Debian**:
```bash
sudo apt update
```
```bash
sudo apt install -y openssh-server
```
```bash
sudo systemctl enable --now ssh
```

#### 1.2 (Optional) Exchange SSH Keys for Passwordless Access

```bash
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
```
```bash
ssh-copy-id YOUR_DEBIAN_USER@YOUR_DEBIAN_IP
```
```bash
ssh YOUR_DEBIAN_USER@YOUR_DEBIAN_IP
```
Replace `YOUR_DEBIAN_USER` and `YOUR_DEBIAN_IP` with actual user/IP on Debian.

---

### 2. CentOS Analysis & Backup (`analyze.sh`)

1. **Clone or copy** `analyze.sh` onto CentOS.
2. **Edit** the variables:
   - `DEBIAN_USER="YOUR_DEBIAN_USER"`
   - `DEBIAN_IP="YOUR_DEBIAN_IP"`
3. **Make it executable**:
```bash
chmod +x analyze.sh
```
4. **Run**:
```bash
sudo ./analyze.sh
```
5. **Outputs** in `/backup` on CentOS, automatically transferred to Debian:
   - `centos_backup-<DATE>.tar.gz` (backup excluding raw DB data)
   - `migration_report.txt`
   - `postgres_dump.sql` (if PostgreSQL found)
   - `mysql_dump.sql` (if MariaDB/MySQL found)

---

### 3. Debian Restoration & Adaptation (`restore.sh`)

1. **Clone or copy** `restore.sh` to Debian.
2. **Make it executable**:
```bash
chmod +x restore.sh
```
3. **Run**:
```bash
sudo ./restore.sh
```
4. **Interactive Menu** appears:
```
=== Advanced CentOS-to-Debian Migration Toolkit ===
1. Analyze migration data and report
2. Check available disk space
3. Backup current Debian system
4. Automatic smart package installation
5. Adapt and safely restore configurations (incl. DB auto-fix & import)
6. Automatic fix for permission issues
7. Enable and restart migrated services
8. Verify restored data
9. Generate detailed migration summary report
10. Rollback changes (Restore Debian from backup)
11. Exit
Choose an option:
```

#### 3.1 Typical Steps
- **(1) Analyze**: check `migration_report.txt` info  
- **(4) Install packages**: sets up Debian equivalents  
- **(5) Adapt & restore**: copies config files/home directories, tries auto-fix for PostgreSQL if needed, imports SQL dumps  
- **(7) Enable & restart** services  
- **(8) Verify** (checks Apache & DBs)  
- **(9) Generate summary** (final recommendations)

---

### 4. Confirming Services

**Apache**:
```bash
curl http://YOUR_DEBIAN_IP/
```
Should show the migrated web content from CentOS.

**PostgreSQL**:
```bash
sudo -u postgres psql -l
```
Look for your migrated databases (e.g., `testdb`).

**MariaDB/MySQL**:
```bash
mysql -e "SHOW DATABASES;"
```
Check for your migrated DB (e.g., `testmdb`).

---

### 5. Rollback (Optional)

If something is wrong, select:
```
(10) Rollback changes (Restore Debian from backup)
```
This restores the Debian backup created in step (3) of the menu.

---

## Final Notes

- **Version Compatibility**  
  If older DB versions exist on CentOS and Debian is using newer ones, the script’s logical dumps typically import fine. It will attempt auto-fixes if needed.

- **Security**  
  - Consider disabling root SSH logins, using key-based auth.  
  - Adjust firewalls on CentOS/Debian as needed.

Check the [LICENSE](LICENSE) file for more details on usage.

Enjoy your automated migration from **CentOS** to **Debian**!  

For logs/troubleshooting:
- **On CentOS**: watch `analyze.sh` output  
- **On Debian**: see `/backup/migration_restore.log` and final summary  
Contributions are welcome!
