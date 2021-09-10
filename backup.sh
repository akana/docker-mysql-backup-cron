#!/bin/bash

# Generate a (gzipped) dumpfile for each database specified in ${DBS}.
# Upload to the given type of storage

. /etc/container_environment.sh

# Bailout if any command fails
set -e

. /_validate.sh


file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# Specify mysql host (mysql by default)
MYSQL_HOST=${MYSQL_HOST:-mysql}
file_env "MYSQL_ROOT_PASSWORD"
MYSQLDUMP_OPTIONS=${MYSQLDUMP_OPTIONS:-"--single-transaction=true"}

# Create a temporary directory to hold the backup files.
find /tmp -type d | grep -v "^/tmp$" | xargs rm -fr
DIR=$(mktemp -d)

# Generate a timestamp to name the backup files with.
TS=$(date +%Y-%m-%d-%H%M%S)

# Backup all databases, unless a list of databases has been specified
BASE_DIR=`dirname ${DIR}/${PREFIX}test`
if [ ! -d "$BASE_DIR" ]; then
  mkdir -p $BASE_DIR
fi
if [ -z "$DBS" ]
then
  # Backup all DB's in bulk
  mysqldump -uroot -p$MYSQL_ROOT_PASSWORD -h$MYSQL_HOST --add-drop-database --events --all-databases $MYSQLDUMP_OPTIONS | gzip > $DIR/${PREFIX}all-databases-$TS.sql.gz
else
  # Backup each DB separately
  for DB in $DBS
  do
    mysqldump -uroot -p$MYSQL_ROOT_PASSWORD -h$MYSQL_HOST --add-drop-database -B $DB $MYSQLDUMP_OPTIONS | gzip > $DIR/$PREFIX$DB-$TS.sql.gz
  done
fi

case $STORAGE_TYPE in
  s3)
    # Upload the backups to S3 --region=$REGION
    s3cmd --access_key=$ACCESS_KEY --secret_key=$SECRET_KEY --region=$REGION sync $DIR/ $BUCKET
    ;;
  swift)
    # Upload the backups to Swift
    cd $DIR
    for f in `find . -type f -name "*.sql.gz"`
    do
      # Avoid Authorization Failure error
      swift upload $CONTAINER ${f}
    done
    ;;
  gcs)
    cd $DIR
    gsutil -m cp -r . gs://${GC_BUCKET}
    ;;
  local)
    # cp the backup files in the temp directory to the backup directory
    cd $DIR
    for f in `find . -type f -name "*.sql.gz" | grep "^./${PREFIX}"`
    do
      BASE_DIR=`dirname ${BACKUP_DIR}/${PREFIX}test`
      if [ ! -d "${BASE_DIR}" ]; then
        mkdir -p ${BASE_DIR}
      fi
      cp -f ${f} ${BASE_DIR}
    done
    ;;
esac

# Clean up
rm -rf $DIR
