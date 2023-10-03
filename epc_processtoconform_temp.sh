BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
BASE_FOLDER_FUNCTIONLIBRARY="/home/sshuser/Test_Automation/FunctionLibrary"
. $BASE_FOLDER/inbound_environment.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_epc_arrival_process.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_epc_process_conformed.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_epc_conformed_staging.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_epc_staging_3nf.sh

NUM=$1
FILENAME=$2

#Getting the sequence numbers
SEQUENCE=`sqlplus -s $DB_CONNECTION <<EOF
set head off feedback off
SELECT A.SEQ_NO FROM TESTING_CONFIG A, TESTING_JOBS B WHERE A.SEQ_NO=B.SEQ_NO AND A.INTERFACE_ID='4.8.7' AND B.STAGE='PROCESS' ORDER BY A.SEQ_NO ASC;
exit;
EOF`

echo SEQUENCE: $SEQUENCE

valid=0

arr=(`echo ${SEQUENCE}`); #Assigning sequence numbers to Array 
for i in "${arr[@]}"
do

if [ $NUM -eq $i ]
then
valid=1
break
fi

done

if [ $valid -eq 1 ]
then
echo VALID SEQUENCE

#function call processtoconform
processtoconform $FILENAME $i


else
echo INVALID SEQUENCE
fi