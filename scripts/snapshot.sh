#!/bin/bash

trap cleanup EXIT

BASE="/backup"
SNAPSHOT_DIR="$BASE/snapshots"
TMP_DIR="$BASE/tmp"
LOG_DIR="$BASE/logs"
HOME_STAGE="$TMP_DIR/home_stage"

TIMESTAMP=$(date +"%Y-%m-%d_%H%M")
CURRENT_SNAP="$SNAPSHOT_DIR/$TIMESTAMP"

LOG_FILE="$BASE/logs/snapshot.log"
LOCK_FILE="/tmp/snapshot.lock"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting snapshot: $TIMESTAMP"

set -e

create_snapshot_dir(){
	mkdir -p "$CURRENT_SNAP"
	echo "Created snapshot directory: $CURRENT_SNAP"
}

backup_etc(){
	echo "Backing up /etc..."

	tar -czf "$CURRENT_SNAP/etc.tar.gz" /etc 2>/dev/null

	echo "/etc backup completed"
}

backup_home(){

	echo "Backing up filtered /home..."

	mkdir -p "$HOME_STAGE"

	cp -r /home/*/.bashrc "$HOME_STAGE" 2>/dev/null || true
	cp -r /home/*/.profile "$HOME_STAGE" 2>/dev/null || true
	cp -r /home/*/.config "$HOME_STAGE" 2>/dev/null || true

	tar -czf "$CURRENT_SNAP/home.tar.gz" -C "$TMP_DIR" home_stage

	rm -rf "$HOME_STAGE"

	echo "/home backup completed"
}

generate_metadata(){

	echo "Generating metadata..."

	{
		echo "Snapshot Time: $(date)"
		echo "Hostname: $(hostname)"
		echo "Kernal: $(uname -r)"
		echo

		echo "Disk Usage:"
		df -h
		echo

		echo "Installed Packages:"
		dpkg --get-selections

	} > "$CURRENT_SNAP/meta.txt"

	echo "Metadata generated"
}

backup_log(){

	echo "Backing up logs..."

	mkdir -p "$TMP_DIR/logs"

	find /var/log -type f -name "*.log" -size -5M \
		-exec cp {} "$TMP_DIR/logs/" \; 2>/dev/null || true

	tar -czf "$CURRENT_SNAP/logs.tar.gz" -C "$TMP_DIR" logs

	rm -rf "$TMP_DIR/logs"

	echo "Logs backup completed"
}

rotate_snapshots(){

	echo "Checking snapshot retention..."

	SNAPSHOTS=$(ls -1tr "$SNAPSHOT_DIR")

	SNAP_COUNT=$(ls -1tr "$SNAPSHOT_DIR" | wc -l)

#	echo "SNAP_COUNT = $SNAP_COUNT"
#	echo "SNAPSHOTS = $SNAPSHOTS"

	if [ "$SNAP_COUNT" -le 3 ]; then
		echo "No old snapshots to delete"

		return

	fi

	DELETE_COUNT=$((SNAP_COUNT - 3))

	echo "$SNAPSHOTS" | head -n "$DELETE_COUNT" | while read OLD; do

		  rm -rf "$SNAPSHOT_DIR/$OLD"

		  echo "Deleted oldest snapshot: $OLD"

	done
}

check_disk() {

	AVAILABLE=$(df /backup | awk 'NR==2 {print $4}')

	# convert KB to MB threshold (example: 500MB minimum free)
	if [ "$AVAILABLE" -lt 500000 ]; then
	  log "ERROR: Low disk space. Snapshot aborted."
	  exit 1
	fi

	log "Disk check passed"
}

acquire_lock() {

	if [ -f "$LOCK_FILE" ]; then

	  log "ERROR: Another snapshot process is already running."

	fi

	touch "$LOCK_FILE"

	log "Lock acquired"
}

cleanup() {

	rm -f "$LOCK_FILE"

	log "Lock released"
}

log "====> SNAPSHOT START <===="

acquire_lock
check_disk
create_snapshot_dir
backup_etc
backup_home
generate_metadata
backup_log
rotate_snapshots
