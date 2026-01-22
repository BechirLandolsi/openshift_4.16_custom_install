#copy all files to be saved on the aws s3 bucket

bucket=$1

tar cvf installer-files.tar installer-files
aws s3 cp installer-files.tar s3://$bucket/installer-files.tar

