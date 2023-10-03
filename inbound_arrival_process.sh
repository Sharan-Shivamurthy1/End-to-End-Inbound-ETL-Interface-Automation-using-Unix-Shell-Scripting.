BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
. $BASE_FOLDER/inbound_environment.sh

PREFIX=$1

FLAG=0


#Getting the files from the sample directory
cd $sample_file_path
var=$(find . -type f -iname $PREFIX"*")
arr=(`echo ${var}`);
cd -

#Loop over the files
for i in "${arr[@]}"
do

#getting the corresponding file_name
FILENAME=${i:2}
echo FILENAME: $FILENAME

currentdate=`date +%y/%m/%d-%H:%M:%S`
echo currentdate $currentdate

LINE=$(grep -n "FILENAME="$FILENAME $BASE_FOLDER/inbound_config.sh | cut -d : -f 1) #Getting the line numbers which are matching with the FILENAME  
echo LINE $LINE

arr=(`echo ${LINE}`); #Assigning matching line numbers to Array 
for i in "${arr[@]}"
do
ENDLINE=(`expr $i + $num`)
count=`expr $i + 1`
#Fetching data from config file
while [ $count -lt $ENDLINE ]
do

if [ -z "$SEQ_NUM" ]
then			
SEQ_NUM=$(sed -n "${count} s/^ *SEQ_NUM=*//p" inbound_config.sh)
fi

if [ -z "$EXPECTEDSTATUS" ]
then			
EXPECTEDSTATUS=$(sed -n "${count} s/^ *EXPECTED_STATUS=*//p" inbound_config.sh)
fi

count=`expr $count + 1`
done
echo FILE_NAME: $FILENAME
echo SEQ_NUM: $SEQ_NUM
echo EXPECTED_STATUS: $EXPECTEDSTATUS
#End of Fetching data from config file

#Getting the interface_details from the TESTING_CONFIG table
var=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT INTERFACE_ID, INTERFACE_NAME, INTERFACE_SUBTYPE, SOURCE_NAME FROM TESTING_CONFIG WHERE SEQ_NO=$SEQ_NUM; 
exit;
EOF`

INTERFACEID=$(echo $var | awk -F '[ ]' '{print $1}')
INTERFACENAME=$(echo $var | awk -F '[ ]' '{print $2}')
SUBTYPE=$(echo $var | awk -F '[ ]' '{print $3}')
SOURCENAME=$(echo $var | awk -F '[ ]' '{print $4}')

echo INTERFACE_ID: $INTERFACEID
echo INTERFACE_NAME: $INTERFACENAME
echo INTERFACE_SUBTYPE: $SUBTYPE
echo SOURCE_NAME: $SOURCENAME
#End of Getting the interface_details from the TESTING_CONFIG table


#Getting JOB_NAME from the TESTING_JOBS table
JOBNAME=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT JOB_NAME FROM TESTING_JOBS WHERE SEQ_NO=$SEQ_NUM AND STAGE='PROCESS'; 
exit;
EOF`

echo JOB_NAME: $JOBNAME
JOBNAME=$(echo $JOBNAME | sed -e 's/[\r\n]//g')
#End of Getting JOB_NAME from the TESTING_JOBS table


#Getting control table details
var=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT ARRIVALS_DIR_PATH, PROCESS_DIR_PATH, ERROR_DIR_PATH FROM INTERFACE_FILE_MASTER WHERE INTERFACE_ID='$INTERFACEID' AND INTERFACE_NAME='$INTERFACENAME' AND INTERFACE_SUB_TYPE='$SUBTYPE'; 
exit;
EOF`

arrdirpath=$(echo $var | awk -F '[ ]' '{print $1}')
procdirpath=$(echo $var | awk -F '[ ]' '{print $2}')
errdirpath=$(echo $var | awk -F '[ ]' '{print $3}')

#Moving the File to arrival directory from local folder
echo File is moving to the Arrival directory $arrdirpath
cp -v $sample_file_path/$FILENAME $arrdirpath
if [ $EXPECTEDSTATUS = 1 ]  #Positive Scenario
then
echo POSITIVE SCENARIO
if [ $arrdirpath/$FILENAME ]  #Checking for File availability in the arrival directory
then
echo FILE AVAILABLE IN THE ARRIVAL DIRECTORY

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_AVAILABILITY','FILE_AVAILABILITY_ARRIVAL','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF


#Getting the record count of the file in the arrival directory
arrival_count=$(wc -l < $arrdirpath/$FILENAME)
echo $count
#getting the data from the file in arrival directory
arr_data=$(<$arrdirpath/$FILENAME)
echo $arr_data
if [ $wrapper_directory/$JOBNAME ]  #Checking for job availability
then
echo JOB PRESENT IN THE WRAPPERS

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_AVAILABILITY','JOB_AVAILABILITY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

#Executing the job
echo Job Starts.....
sh $wrapper_directory/$JOBNAME

#Getting the latest job_run_id
job_run_id=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT MAX(JOB_RUN_ID) FROM JOB_PROCESS_CONTROL WHERE JOB_ID=(SELECT JOB_ID FROM JOB_MASTER WHERE JOB_NAME ='$JOBNAME'); 
exit;
EOF`
echo job_run_id $job_run_id

var=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT JOB_RUN_STATUS, TO_CHAR(JOB_START_DATE_TIME,'YY/MM/DD-HH24:MI:SS') FROM JOB_PROCESS_CONTROL WHERE JOB_RUN_ID=$job_run_id;
exit;
EOF`

#getting job_run_status
job_run_status=$(echo $var | awk -F '[ ]' '{print $1}')
#getting the job_start_time
job_start_time=$(echo $var | awk -F '[ ]' '{print $2}')
echo job_run_status $job_run_status
echo job_start_time $job_start_time

date_valid=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT COUNT(*) FROM DUAL WHERE TO_TIMESTAMP('$job_start_time','YY/MM/DD-HH24:MI:SS')>=TO_TIMESTAMP('$currentdate','YY/MM/DD-HH24:MI:SS');
exit;
EOF`

if [ $date_valid = 1 ]  #Check for valid JOB_RUN_ID
then

echo JOB_RUN_ID CREATED
if [ $job_run_status = 1 ]  #JOB_PROCESS_CONTROL check
then
echo JOB EXECUTED SUCCESSFULLY

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_EXECUTION','JOB_PROCESS_CONTROL CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #JOB_PROCESS_CONTROL check
echo JOB FAILED

FLAG=1
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_EXECUTION','JOB_PROCESS_CONTROL CHECK','FAILED','JOB_RUN_STATUS in JOB_PROCESS_CONTROL table is ${job_run_status}',SYSTIMESTAMP,'INBOUND');
exit;
EOF
fi  #JOB_PROCESS_CONTROL check


var=$(hadoop fs -ls $adlpath$procdirpath/$FILENAME)
if [ "$var" != "" ]  #file availability in process
then
echo FILE IS IN PROCESS DIR

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','PROCESS_DIR CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

#getting data from FILE_CONTROL table
file_processing_status=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT FILE_PROCESSING_STATUS FROM FILE_CONTROL WHERE JOB_RUN_ID=$job_run_id;
exit;
EOF`
echo $file_processing_status

if [ $file_processing_status = 1 ]  #File control check
then
echo FILE PROCESSING PASSED

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

elif [ $file_processing_status = 2 ]  #File control check
then
echo FILE IS MOVED TO ERROR

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','FAILED','File is moved to error directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #File control check
echo FILE PROCESSING FAILED

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','FAILED','FILE_CONTROL table entry is ${file_processing_status}',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #File control check

#getting count of records in process
process_count=$(hadoop fs -cat $adlpath$procdirpath/$FILENAME | wc -l)
echo $process_count
if [ $process_count -eq $arrival_count ]  #count check
then
echo RECORD COUNT MATCHING

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','RECORD_COUNT_CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #count check
echo RECORD COUNT MISMATCH

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','RECORD_COUNT_CHECK','FAILED','Record count is not matching arrival ${arrival_count} process ${process_count}',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #count check

#getting data from the file in process dir
process_data=$(hadoop fs -cat $adlpath$procdirpath/$FILENAME)
echo $process_data
if [ "$process_data" == "$arr_data" ]  #data check
then
echo DATA IS MATCHING

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','DATA_VALIDATION','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #data check
echo DATA MISMATCH

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','DATA_VALIDATION','FAILED','Data is not matching in arrival and process',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #data check

else  #file availability in process
echo FILE IS NOT AVAILABLE IN THE PROCESS DIR

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','PROCESS_DIR CHECK','FAILED','File is not available in the process directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #file availability in process

#file availability in error directory
var=$(hadoop fs -ls $adlpath$errdirpath/$FILENAME)
if [ "$var" != "" ]  #file availability in error directory
then
echo FILE PRESENT IN THE ERROR DIR

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','ERROR_CHECK','ERROR_DIRECTORY_CHECK','FAILED','File is available in the error directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #file availability in error directory
echo FILE NOT PRESENT IN THE ERROR

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','ERROR_CHECK','ERROR_DIRECTORY_CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #file availability in error directory

else  #Check for valid JOB_RUN_ID
echo JOB_RUN_ID IS NOT CREATED

fi  #Check for valid JOB_RUN_ID


else  #job availability
echo JOB IS NOT AVAILABLE IN THE WRAPPERS

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','$JOB_AVAILABILITY','JOB_AVAILABILITY','FAILED','Job is not present in wrappers',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #End of job availability

else  #File availability in the arrival directory
echo FILE IS NOT PRESENT IN THE ARRIVAL DIRECTORY

FLAG=1

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','$FILE_AVAILABILITY','FILE_AVAILABILITY_ARRIVAL','FAILED','File is not present in the arrivals path',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #End of File availability in the arrival directory


elif [ $EXPECTEDSTATUS = 2 ]  #Negative Scenario
then

FLAG=1

echo NEGATIVE SCENARIO
if [ $arrdirpath/$FILENAME ]  #Checking for File availability in the arrival directory
then
echo FILE AVAILABLE IN THE ARRIVAL DIRECTORY
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','NEGATIVE','FILE_AVAILABILITY','FILE_AVAILABILITY_ARRIVAL','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF













else  #Checking for File availability in the arrival directory
echo FILE NOT PRESENT IN THE ARRIVAL

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','ARRIVAL TO PROCESS','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','NEGATIVE','$FILE_AVAILABILITY','FILE_AVAILABILITY_ARRIVAL','FAILED','File is not present in the arrivals path',SYSTIMESTAMP,'INBOUND');
exit;
EOF


fi  #Checking for File availability in the arrival directory


fi
done


SEQ_NUM=""
EXPECTEDSTATUS=""


#Increment the loop control variable
FILE_NUMBER=`expr $FILE_NUMBER + 1`
done
#End of looping file processing