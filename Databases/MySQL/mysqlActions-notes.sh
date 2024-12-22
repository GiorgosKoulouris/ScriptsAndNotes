# Export DB to file
mysqldump -u username -p database_name > file.sql

# Import DB from file
mysql -u username -p database_name < file.sql
