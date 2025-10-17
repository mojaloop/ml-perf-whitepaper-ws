#!/bin/sh
# Dump all MySQL databases from mysqldb-0 in mojaloop namespace

POD=mysqldb-0
NAMESPACE=mojaloop
USER=root
PASSWORD=""
BACKUP_DIR="/path/to/local/backup/directory"
DATE=$(date +%F_%H-%M-%S)
DUMP_FILE=all-databases.sql

echo "Creating local backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo "Dumping all databases from pod $POD ..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  sh -c "mysqldump -u$USER -p$PASSWORD --all-databases --single-transaction --quick --lock-tables=false" \
  > "$BACKUP_DIR/$DUMP_FILE"

if [ $? -eq 0 ]; then
  echo "Backup complete: $BACKUP_DIR/$DUMP_FILE"
else
  echo "Backup failed!"
  exit 1
fi