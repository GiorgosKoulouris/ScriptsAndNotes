import boto3
import os
from pathlib import Path
from botocore.exceptions import NoCredentialsError, ClientError
import time
from datetime import datetime
import logging
import sys

def getVarValue(varKey):
    varValue = None
    with open(varFile, 'r') as file:
        for line in file:
            if line.startswith(varKey + '='):
                varValue = line.strip().split('=')[1]
                break

    if not varValue:
        raise ValueError( varKey + " not found in " + varFile)
    else:
        return varValue

# Set up logging
def setup_logging(log_dir):

    # Ensure the directory exists
    os.makedirs(log_dir, exist_ok=True)

    # Log file path
    current_date = datetime.now().strftime("%Y%m%d")
    log_file = os.path.join(log_dir, f"{current_date}_dbBackups.log")

    # Create a logger
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)

    # Create a file handler to log to a file
    file_handler = logging.FileHandler(log_file)
    fileDebugLevel = getVarValue('BACKUP_UPLOAD_JOB_LOG_LEVEL')
    if fileDebugLevel == 'DEBUG':
        file_handler.setLevel(logging.DEBUG)
    else:
        file_handler.setLevel(logging.INFO)

    # Create a console handler to log to console
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)  # Log INFO level to console

    # Define log format
    log_format = '%(asctime)s - %(message)s'
    formatter = logging.Formatter(log_format, datefmt='%Y-%m-%d %H:%M:%S %z')
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)

    # Add the handlers to the logger
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

def upload_files_to_s3(file_path, bucket_name, s3_prefix=""):
    # Create an S3 client using EC2 metadata authentication
    s3_client = boto3.client('s3')

    file_path = Path(file_path)
    filename = Path(file_path).name

    try:
        if file_path.is_file():  # Process files only
            # Create the full S3 path, including the optional prefix
            s3_key = str(Path(s3_prefix) / filename)

            # Upload the file if it's modified or doesn't exist on S3
            logging.info(f"Uploading {file_path} to s3://{bucket_name}/{s3_key}")
            s3_client.upload_file(str(file_path), bucket_name, s3_key)
            logging.info(f"Successfully uploaded {file_path} to s3://{bucket_name}/{s3_key}")
        else:
            logging.error(f"ERROR: Skipping {file_path}. File does not exist.")
            exit(1)

    except NoCredentialsError:
            logging.error(f"ERROR: No credentials found. Make sure the EC2 instance has an IAM role with S3 access.")
    except Exception as e:
        logging.error(f"ERROR: Failed to upload {file_path}. Error: {e}")

if __name__ == "__main__":
    # Check if an argument is provided
    if len(sys.argv) != 2:
        logging.error("ERROR: Invalid argument count. Exiting...")
        exit(1)
    else:
        backupFile = sys.argv[1]  # The second argument is the first user-provided argument

    varFile = "variables.txt"

    logDir = getVarValue('SCRIPT_LOG_DIR')
    setup_logging(logDir)

    backupDirectory = getVarValue('BACKUP_DIR')
    bucketName = getVarValue('BUCKET_NAME')
    s3Prefix = getVarValue('BUCKET_PREFIX_BACKUPS')
    upload_files_to_s3(backupFile, bucketName, s3Prefix)

