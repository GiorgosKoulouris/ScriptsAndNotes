#!/bin/bash

# Compresses logs older that 1 day and deletes older that 7 days

LOGS_DIRECTORY="/path/to/logs"
COMPRESS_OLDER_THAN=1
DELETE_OLDER_THAN=7

find "$LOGS_DIRECTORY" -type f -name "repoSync_*.log" -mtime "+$COMPRESS_OLDER_THAN" -exec tar -czf {}.tar.gz {} \; -exec rm -f {} \;
find "$LOGS_DIRECTORY" -type f -name "repoSync_*.log.tar.gz" -mtime "+$DELETE_OLDER_THAN" -exec rm -f {} \;
