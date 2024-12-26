import boto3
from botocore.exceptions import NoCredentialsError, PartialCredentialsError
import os
from datetime import datetime, timezone
import logging
import subprocess
import re
from tzlocal import get_localzone
import glob


def getVarValue(varKey):
    varValue = None
    with open(varFile, "r") as file:
        for line in file:
            if line.startswith(varKey + "="):
                varValue = line.strip().split("=")[1]
                break

    if not varValue:
        raise ValueError(varKey + " not found in " + varFile)
    else:
        return varValue

def convertTimeToSystemNative(time):

    match = re.search(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (\+\d{4})", time)

    if match:
        datetime_part = match.group(1)  # '2025-12-24 04:51:00'
        timezone_part = match.group(2)  # '+0200'

        # Combine the date and time into one string with the timezone part
        dt_str = f"{datetime_part} {timezone_part}"

        # Parse the datetime string and create a timezone-aware datetime object
        fmt = "%Y-%m-%d %H:%M:%S %z"
        original_dt = datetime.strptime(dt_str, fmt)

        # Get the system's local timezone
        local_timezone = get_localzone()  # This gets the local timezone dynamically

        # Convert the datetime object to the system's local timezone
        local_dt = original_dt.astimezone(local_timezone)

        # Format the result into the final format without timezone offset
        formatted_local_dt = local_dt.strftime("%Y-%m-%d %H:%M:%S")
        return formatted_local_dt
    else:
        logging.error("ERROR: No match found in the text.")


# Set up logging
def setup_logging(log_dir):

    # Ensure the directory exists
    os.makedirs(log_dir, exist_ok=True)

    # Log file path
    current_date = datetime.now().strftime("%Y%m%d")
    log_file = os.path.join(log_dir, f"{current_date}_dbRestore.log")

    # Create a logger
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)

    # Create a file handler to log to a file
    file_handler = logging.FileHandler(log_file)
    fileDebugLevel = getVarValue("LOG_UPLOAD_JOB_LOG_LEVEL")
    if fileDebugLevel == "DEBUG":
        file_handler.setLevel(logging.DEBUG)
    else:
        file_handler.setLevel(logging.INFO)

    # Create a console handler to log to console
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)  # Log INFO level to console

    # Define log format
    log_format = "%(asctime)s - %(message)s"
    formatter = logging.Formatter(log_format, datefmt="%Y-%m-%d %H:%M:%S")
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)

    # Add the handlers to the logger
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

def createBackupAndDropDatabase(dbName, backupDir):
    now = datetime.now()
    formattedNow = now.strftime('%Y%m%d_%H%M%S')
    fileName = dbName + '_bak_' + formattedNow + '.sql'
    backupFile = os.path.join(backupDir, fileName)
    command = ["mysqldump", dbName]
    try:
        logging.info(f"Creating dump of database {dbName}.")
        with open(backupFile, "w") as f:
            subprocess.run(command, stdout=f)
        logging.info(f"Dump created successfully. Dump file: {backupFile}")
    except:
        logging.error(f"Database {dbName} could not be dumped.")
        exit(1)
        
    command = ["mysql", '-e', f"drop database {dbName};"]
    try:
        logging.info(f"Dropping database {dbName}.")
        subprocess.run(command)
        logging.info(f"Database dropped successfully.")
    except:
        logging.error(f"Database {dbName} could not be dropped.")
        exit(1)
        
    command = ["mysql", '-e', f"create database {dbName};"]
    try:
        logging.info(f"Creating empty database {dbName}.")
        subprocess.run(command)
        logging.info(f"Database created successfully.")
    except:
        logging.error(f"Database {dbName} could not be created.")
        exit(1)

def downloadLatestBackupBeforeTimestamp(
    bucket_name, prefix, cutoff_datetime_str, download_dir
):
    """
    Download the latest file from an S3 bucket with a specific prefix, if its last modified date is earlier than the given datetime.
    Only files (not folders) will be considered.

    :param bucket_name: The S3 bucket name
    :param prefix: The S3 prefix (folder path)
    :param cutoff_datetime_str: The datetime string (e.g., '2023-12-01 00:00:00 +0200') to compare LastModified
    :param download_dir: Directory to download the file to
    """
          
    # Empty the download directory
    items = os.listdir(download_dir)
    for item in items:
        item_path = os.path.join(download_dir, item)
        
        # If the item is a file, delete it
        if os.path.isfile(item_path):
            try:
                os.remove(item_path)
                logging.info(f"Deleted file: {item_path}")
            except Exception as e:
                logging.error(f"Error deleting file {item_path}: {e}")
                raise
        else:
            logging.info(f"Skipping directory: {item_path}")

        
    # Convert the given datetime string to a datetime object
    cutoff_datetime = datetime.strptime(cutoff_datetime_str, "%Y-%m-%d %H:%M:%S %z")
    # Initialize the S3 client
    s3_client = boto3.client("s3")

    latest_file = None
    latest_modified = None

    try:
        # List objects in the S3 bucket with the given prefix
        response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

        # Check if 'Contents' is in the response (i.e., the bucket isn't empty)
        if "Contents" in response:
            for obj in response["Contents"]:
                # Skip objects that represent folders (keys ending with '/')
                if obj["Key"].endswith("/"):
                    continue

                # Get the LastModified timestamp of the object
                last_modified = obj["LastModified"]

                # Only consider files with a LastModified timestamp earlier than the cutoff datetime
                if last_modified < cutoff_datetime:
                    # If it's the latest file we've encountered so far, update the latest_file
                    if latest_modified is None or last_modified > latest_modified:
                        latest_file = obj
                        latest_modified = last_modified

            if latest_file:
                # Download the latest file before the cutoff datetime
                s3_key = latest_file["Key"]
                local_file_path = os.path.join(download_dir, os.path.basename(s3_key))

                logging.info(
                    f"Downloading the latest backup: {s3_key} (Last Modified: {latest_modified})"
                )
                s3_client.download_file(bucket_name, s3_key, local_file_path)
                logging.info(f"Downloaded backup {local_file_path} successfully.")
                decompress_command = ["gzip", "-d", local_file_path]
                subprocess.run(decompress_command)
                local_file_path = os.path.splitext(local_file_path)[0]
                logging.info(f"Decompressed backup {local_file_path}.")
                return local_file_path
            else:
                logging.info(
                    "No files found that were modified before the specified timestamp."
                )
                exit(0)

        else:
            logging.info("No objects found in the specified bucket/prefix.")

    except NoCredentialsError:
        logging.error("ERROR: No AWS credentials found.")
    except PartialCredentialsError:
        logging.error("ERROR: Incomplete AWS credentials found.")
    except Exception as e:
        logging.error(f"ERROR: An error occurred: {e}")


def downloadLogs(bucket_name, prefix, download_dir):
    """
    Download the latest file from an S3 bucket with a specific prefix, if its last modified date is earlier than the given datetime.
    Only files (not folders) will be considered.

    :param bucket_name: The S3 bucket name
    :param prefix: The S3 prefix (folder path)
    :param download_dir: Directory to download the file to
    """
        
    # Empty the download directory
    items = os.listdir(download_dir)
    for item in items:
        item_path = os.path.join(download_dir, item)
        
        # If the item is a file, delete it
        if os.path.isfile(item_path):
            try:
                os.remove(item_path)
                logging.info(f"Deleted file: {item_path}")
            except Exception as e:
                logging.error(f"Error deleting file {item_path}: {e}")
                raise
        else:
            logging.info(f"Skipping directory: {item_path}")
            
            
    # Initialize the S3 client
    s3_client = boto3.client("s3")

    try:
        # List objects in the S3 bucket with the given prefix
        response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

        # Check if 'Contents' is in the response (i.e., the bucket isn't empty)
        if "Contents" in response:
            for obj in response["Contents"]:
                # Skip objects that represent folders (keys ending with '/')
                if obj["Key"].endswith("/"):
                    continue

                s3_key = obj["Key"]
                local_file_path = os.path.join(download_dir, os.path.basename(s3_key))
                logging.info(f"Downloading log {s3_key} to {local_file_path}")
                s3_client.download_file(bucket_name, s3_key, local_file_path)
                logging.info(f"Downloaded log {local_file_path}.")

        else:
            logging.info("No objects found in the specified bucket/prefix.")

    except NoCredentialsError:
        logging.error("ERROR: No AWS credentials found.")
    except PartialCredentialsError:
        logging.error("ERROR: Incomplete AWS credentials found.")
    except Exception as e:
        logging.error(f"ERROR: An error occurred: {e}")

def extract_log_file_and_position(backup_file_path):
    logging.info("Retrieving log starting point in the backup file.")
    # Define a regex pattern to match the -- CHANGE MASTER TO line
    pattern = re.compile(b"--\s*CHANGE MASTER TO MASTER_LOG_FILE='([^']+)',\s*MASTER_LOG_POS=(\d+);")
    
    # Open the backup file
    with open(backup_file_path, 'rb') as file:
        # Read the entire file
        content = file.read()
    
    # Search for the CHANGE MASTER TO pattern
    match = pattern.search(content)
    
    if match:
        # Extract the binary log file and position
        log_file = match.group(1)
        log_pos = int(match.group(2))
        return log_file.decode('utf-8'), log_pos
    else:
        raise ValueError("No CHANGE MASTER TO line found in the backup file.")


def restore_database(backup_file, db_name):
    """Restores the database from the backup file."""
    logging.info(f"Restoring database {db_name} from {backup_file}...")
    restore_command = ["mysql", db_name]
    try:
        with open(backup_file, "r") as f:
            subprocess.run(restore_command, stdin=f)
        logging.info(f"Database {db_name} restored successfully.")
    except:
        logging.error(f"Database {db_name} could not be restored.")
        exit(1)

def apply_combined_binary_logs(binlog_dir, db_name, startLog, startPosition, end_time):
    """Applies combined binary logs for the database within the time range."""
    logging.info(
        f"Applying combined binary logs for {db_name} from log {startLog} (position {startPosition}) to {end_time}..."
    )
    for filename in os.listdir(binlog_dir):
        file_path = os.path.join(binlog_dir, filename)
        
        # Check if it's a file and ends with .index
        if os.path.isfile(file_path) and filename.endswith(".index"):
            try:
                os.remove(file_path)
                logging.info(f"Deleted: {file_path}")
            except Exception as e:
                logging.error(f"Error deleting {file_path}: {e}")

        elif os.path.isfile(file_path) and not filename.endswith(".index"):
            if file_path < startLog:
                try:
                    os.remove(file_path)
                    logging.info(f"Deleted {file_path}: as it's older than the start log.")
                except Exception as e:
                    logging.error(f"Error deleting {file_path}: {e}")
            
    conbinedLogFile = os.path.join('/tmp', 'replay_logs.sql')
    
    # Expand the wildcard for log files
    log_files = glob.glob(f"{binlog_dir}/*")
   
    command = [
    "mysqlbinlog",
    "--start-position=" + str(startPosition),
    "--stop-datetime=" + end_time,
    "--database=" + db_name,
    "--result-file=" + conbinedLogFile,
    ] + log_files

    logging.info(f"Creating combined log...")
    try:
        subprocess.run(command, check=True)
        logging.info(f"Created combined log at {conbinedLogFile}.")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error creating binary log {conbinedLogFile}: {e}")
        raise
    apply_logs_to_mysql(conbinedLogFile, db_name, end_time)


def apply_logs_to_mysql(combined_logs, db_name, end_time):
    """Applies the combined logs to MySQL in a single command."""
    try:
        with open(combined_logs, "r") as f:
            command = ['mysql', db_name]
            subprocess.run(command, stdin=f)
            logging.info(f"Applied logs until {end_time}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error applying replay logs: {e}")

if __name__ == "__main__":
    # Input parameters
    varFile = "variables.txt"

    logDir = getVarValue("SCRIPT_LOG_DIR")
    setup_logging(logDir)

    dbName = getVarValue("DB_NAME")
    bucket_name = getVarValue("BUCKET_NAME")
    backupsPrefix = getVarValue("FULL_BACKUPS_S3_PREFIX")
    logsPrefix = getVarValue("DB_LOGS_S3_PREFIX")
    restorePointTime = getVarValue("RESTORE_TIME")
    backupDownloadDir = os.path.join(getVarValue("DOWNLOAD_DIR"), "backups")
    logDownloadDir = os.path.join(getVarValue("DOWNLOAD_DIR"), "logs")
    currentBackupDir = getVarValue("CURRENT_BACKUP_DIR")

    # Ensure the download directories exist
    if not os.path.exists(backupDownloadDir):
        os.makedirs(backupDownloadDir)
    if not os.path.exists(logDownloadDir):
        os.makedirs(logDownloadDir)
    if not os.path.exists(currentBackupDir):
        os.makedirs(currentBackupDir)

    # createBackupAndDropDatabase(dbName, currentBackupDir)
    backup_file = downloadLatestBackupBeforeTimestamp(
        bucket_name, backupsPrefix, restorePointTime, backupDownloadDir
    )
    downloadLogs(bucket_name, logsPrefix, logDownloadDir)
    start_log_file, start_log_pos = extract_log_file_and_position(backup_file)
    startLogFilePath = os.path.join(logDownloadDir, start_log_file)
    restore_database(backup_file, dbName)
    apply_combined_binary_logs(
        logDownloadDir, dbName, startLogFilePath, start_log_pos, convertTimeToSystemNative(restorePointTime)
    )

