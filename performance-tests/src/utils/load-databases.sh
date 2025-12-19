#!/bin/sh
# Restore all MySQL databases to mysqldb-0 in mojaloop namespace

POD=mysqldb-0
NAMESPACE=mojaloop
USER=root
PASSWORD=""
BACKUP_FILE=/path/to/local/backup/directory/all-databases.sql

if [ ! -f "$BACKUP_FILE" ]; then
  echo "File not found: $BACKUP_FILE"
  exit 1
fi

echo "Copying $BACKUP_FILE into pod $POD ..."
kubectl cp "$BACKUP_FILE" "$NAMESPACE/$POD:/tmp/restore.sql"

echo "Restoring all databases ..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
  sh -c "mysql -u$USER -p$PASSWORD < /tmp/restore.sql"

if [ $? -eq 0 ]; then
  echo "Restore completed successfully"
else
  echo "Restore failed!"
  exit 1
fi
