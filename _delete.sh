#!/bin/bash

function list_backup_files {
  TMP_OUT="/tmp/list"
  rm -f ${TMP_OUT}
  case $STORAGE_TYPE in
    s3)
      s3cmd --access_key=$ACCESS_KEY --secret_key=$SECRET_KEY --region=$REGION ls $BUCKET > ${TMP_OUT}
      ;;
    swift)
      swift list $CONTAINER > ${TMP_OUT}
      ;;
    local)
      ls ${BACKUP_DIR}/*.gz | xargs -n 1 basename > ${TMP_OUT}
      ;;
  esac
  LATEST_BACKUP=`cat ${TMP_OUT} | grep ${TS_PREFIX} | sort -r | head -1`
  FILTERED_BACKUPS=`cat ${TMP_OUT} | grep ${TS_PREFIX}`
  ALL_BACKUP_FILES=`cat ${TMP_OUT} | sort -r`
  rm -f ${TMP_OUT}
}

function delete {
  case $STORAGE_TYPE in
    s3)
      s3cmd --access_key=$ACCESS_KEY --secret_key=$SECRET_KEY --region=$REGION del $BUCKET/$1
      ;;
    swift)
      swift delete $CONTAINER $1
      ;;
    local)
      rm -f ${BACKUP_DIR}/$1
      ;;
  esac
}

list_backup_files

if [ -n "${LATEST_BACKUP}" ]; then
  for f in ${FILTERED_BACKUPS}
  do
    if [ ${f} != "${LATEST_BACKUP}" ]; then
      delete ${f}
    fi
  done
fi

if [ -n "${ALL_BACKUP_FILES}" ]; then
  NUM_FILES=0
  TODAY=$(date +%Y-%m-%d)
  for f in ${ALL_BACKUP_FILES}
  do
    if [ `echo ${f} | grep ${TODAY}` ]; then
      continue
    fi
    let NUM_FILES=NUM_FILES+1
    if [[ "${NUM_FILES}" -le "${MAX_DAILY_BACKUP_FILES}" ]]; then
      continue;
    fi
    delete ${f}
  done
fi
