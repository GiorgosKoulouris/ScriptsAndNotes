#!/bin/bash

rootStackName="00-AIO-Enroll"
pkgSuffix="Package"

rootStack="$rootStackName.yaml"
pkgStack="$rootStackName-$pkgSuffix.yaml"


#export AWS_DEFAULT_PROFILE=tcop-mng

ACL="public-read" # "public-read" or "private"

aws cloudformation package \
  --template-file $rootStack \
  --s3-bucket tcop-mgmt-cloudformation-stacks \
  --output-template-file $pkgStack

aws s3 cp $pkgStack s3://tcop-mgmt-cloudformation-stacks/$rootStack --acl $ACL

template_files="$(awk '/TemplateURL:/{getline; n=split($0,a,"/"); print a[n]}' "$pkgStack")"
while read -r template; do
  aws s3api put-object-acl --bucket tcop-mgmt-cloudformation-stacks --key $template --acl $ACL && echo "OK: $template" || echo "FAILED $template"
done <<< "$template_files"

echo "Template URL: https://tcop-mgmt-cloudformation-stacks.s3.eu-central-1.amazonaws.com/$rootStack"

# export AWS_DEFAULT_PROFILE=tcop-sbx
# aws cloudformation deploy \
#   --template-file packaged.yaml \
#   --stack-name nested-example \
#   --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

