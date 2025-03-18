# Export DB to file
mysqldump -u username -p database_name > file.sql

# Import DB from file
mysql -u username -p database_name < file.sql

mysqldump \
    --databases database_name \
    --add-drop-database \
    --add-drop-table \
    --create-options \
        > file.sql