#set -x
#waits for the command to be ok (exit 0) or the maximum number of retry is reached
#during each test, waits a specific amount of time, tail the log file provided
#exit 0 anyway

ret=1
let delai=$1*60
let max=$2*60
filelog=$3
filecmd=$4
count=0

while [[ $ret != 0 ]] && [[ $count -lt $max ]]; do 
	timeout -k ${delai}s ${delai}s tail -3f $filelog 
	let count=count+delai
	timeout -k 10s 10s sh -c "$filecmd" 
	let ret=$?
done
exit 0 
