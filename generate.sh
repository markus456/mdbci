#!/bin/bash

# $1 - work dir
# $2 - template name
# $3 destination

work_dir=$1
template_name=$2
dest=$3

rm -rf $dest/$work_dir/$template_name
mkdir -p $dest/$work_dir/$template_name

versions=`cat $work_dir/$template_name.version`

for i in $versions
do
	sed "s|###version###|$i|g" $work_dir/$template_name.json.template > $dest/$work_dir/$template_name/$i.json
done
