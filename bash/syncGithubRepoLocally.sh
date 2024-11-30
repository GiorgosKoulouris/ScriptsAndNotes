#!/bin/bash

# 
# Desription
#   This script checks whether the local repository is in sync with the latest status of a remote repo on GitHub
#   If not, the remote repository is pulled and the local directory gets updated
# 
# 
# Note
#   In order for the script to work, the repo will need to be already cloned locally
# 
# 
# Intructions
#   - The script can sync with both public and private repos. Set the 'PRIVATE_REPO' variable to true in order to use the script against a private repo
# 
#   - In order to sync with private repos, you will need an SSH key with access to the remote repo.
#       The public key will need to have a comment on it. This the script evaluates if the key is added on the ssh-agent or not
# 
#   - If you need, you can schedule the script to get executed every X amount on time (cron etc)
# 
#   - The script can write logs in order to monitor its behaviour.
#       Set the 'WRITE_LOGS' variable to true and define a folder for the logs to be written
# 

# Define the path to the SSH key for GitHub
PRIVATE_REPO="true"                         # true/false
GH_SSH_KEY="/path/to/gihubKey"              # Private SSH key file
GH_SSH_COMMENT="github_ssh_key"             # The comment on the public ssh key that's used for github
LOCAL_REPO_PATH="/path/to/local/repo"       # The directory where the repo is located locally
BRANCH="main"                               # Branch to sync against
WRITE_LOGS="true"                           # true/false
LOGS_DIRECTORY="/path/to/repoSyncLogs"      # Directory where logs will be written

write_log() {
    if [ "$WRITE_LOGS" == 'true' ]; then
        datestamp=$(date +"%Y%m%d")
        logFileName="repoSync_$datestamp.log"
        logFile="$LOGS_DIRECTORY/$logFileName"

        msg="$1"
        timestamp=$(date +"%H:%M:%S")
        echo "$timestamp - $msg" >>"$logFile"
    fi
}

check_prerequisites() {
    # Check that the SSH key exists -- Ignored for public repos
    if [ "$PRIVATE_REPO" == 'true' ]; then
        [ -f "$GH_SSH_KEY" ] || {
            msg="Github SSH key is missing. Exiting..."
            echo "$msg"
            write_log "FAILED: $msg"
            exit 1
        }
    fi

    # Check that the local repository exists
    [ -d "$LOCAL_REPO_PATH" ] || {
        msg="Local repository directory not found. Exiting..."
        echo "$msg"
        write_log "FAILED: $msg"
        exit 1
    }

    # Create the log directory if it doesn't exist (if WRITE_LOGS option is set to true)
    [ "$WRITE_LOGS" == 'true' ] && [ ! -d "$LOGS_DIRECTORY" ] && mkdir "$LOGS_DIRECTORY"
}

load_ssh_key() {
    # Check if the SSH key is already loaded in the SSH agent. If not, add the key
    if ! ssh-add -l | grep -q "$GH_SSH_COMMENT"; then
        # Start the SSH agent if it's not running and add the SSH key
        eval "$(ssh-agent -s)" && ssh-add "$GH_SSH_KEY" && {
            msg="SSH key added."
            echo "$msg"
            write_log "INFO: $msg"
        }
    else
        msg="SSH key is already loaded."
        echo "$msg"
        write_log "INFO: $msg"
    fi
}

sync_repo() {
    # Change to the local repository directory
    cd "$LOCAL_REPO_PATH"

    # Ensure the repository is up-to-date with remote
    git fetch origin || {
        msg="Failed to fetch from remote repository."
        echo "$msg"
        write_log "FAILED: $msg"
        exit 1
    }

    # Check the current status of the local and remote branches
    LOCAL_COMMIT=$(git rev-parse "$BRANCH")
    REMOTE_COMMIT=$(git rev-parse "origin/$BRANCH")

    # Compare the commits
    if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
        msg="Updates found. Pulling changes from the remote repository."
        echo "$msg"
        write_log "INFO: $msg"

        # Pull the changes from the remote repository
        git pull origin "$BRANCH" || {
            msg="Failed to pull changes from remote repository."
            echo "$msg"
            write_log "FAILED: $msg"
            exit 1
        }

    else
        msg="No updates found. The local repository is up-to-date."
        echo "$msg"
        write_log "INFO: $msg"
    fi
}

main() {
    # Check prereqs
    check_prerequisites

    # Load SSH key -- Ignored for public repos
    [ "$PRIVATE_REPO" == 'true' ] && load_ssh_key

    # Perform the sync
    sync_repo
}

main
