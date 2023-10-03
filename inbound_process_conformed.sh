BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
. $BASE_FOLDER/inbound_environment.sh

FILENAME=$1

currentdate=`date +%y/%m/%d-%H:%M:%S`
echo currentdate $currentdate

LINE=$(grep -n "FILENAME="$FILENAME $BASE_FOLDER/inbound_config.sh | cut -d : -f 1) #Getting the line numbers which are matching with the FILENAME  
echo LINE $LINE

arr=(`echo ${LINE}`); #Assigning matching line numbers to Array
#Outer Loop
for i in "${arr[@]}"
do
ENDLINE=(`expr $i + $num`)
count=`expr $i + 1`
#Fetching data from config file
#Inner Loop
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
done  #End of Inner Loop

echo FILE_NAME: $FILENAME
echo SEQ_NUM: $SEQ_NUM
echo EXPECTED_STATUS: $EXPECTEDSTATUS
#End of fetching data from the config file

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
var=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT JOB_NAME, TABLE_NAME FROM TESTING_JOBS WHERE SEQ_NO=$SEQ_NUM AND STAGE='CONFORM'; 
exit;
EOF`

JOBNAME=$(echo $var | awk -F '[ ]' '{print $1}')
HIVE_TABLE=$(echo $var | awk -F '[ ]' '{print $2}')

echo JOB_NAME: $JOBNAME
echo HIVE TABLE NAME: $HIVE_TABLE
JOBNAME=$(echo $JOBNAME | sed -e 's/[\r\n]//g')  #trimming the new line characters
#End of Getting JOB_NAME from the TESTING_JOBS table

#Get the control table data
var=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT PROCESS_DIR_PATH, CONFORMED_DIR_PATH, COMPLETE_DIR_PATH, ERROR_DIR_PATH, REJECT_DIR_PATH FROM INTERFACE_FILE_MASTER WHERE INTERFACE_ID='$INTERFACEID' AND INTERFACE_NAME='$INTERFACENAME' AND INTERFACE_SUB_TYPE='$SUBTYPE'; 
exit;
EOF`

procdirpath=$(echo $var | awk -F '[ ]' '{print $1}')
cnfldirpath=$(echo $var | awk -F '[ ]' '{print $2}')
completedirpath=$(echo $var | awk -F '[ ]' '{print $3}')
errdirpath=$(echo $var | awk -F '[ ]' '{print $4}')
rejdirpath=$(echo $var | awk -F '[ ]' '{print $5}')

echo ProcessDir: $procdirpath
echo ComformedDir: $cnfldirpath
echo CompleteDir: $completedirpath
echo ErrorDir: $errdirpath
echo RejectDir: $rejdirpath

if [ $EXPECTEDSTATUS = 1 ]  #Positive Scenario
then
echo POSITIVE SCENARIO

var=$(hadoop fs -ls $adlpath$procdirpath/$FILENAME)
if [ "$var" != "" ]  #file availability in process
then
echo FILE IS IN PROCESS DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_AVAILABILITY','FILE_AVAILABILITY_PROCESS_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

#Getting Process Record count
process_count=$(hadoop fs -cat $adlpath$procdirpath/$FILENAME | wc -l)
echo Process Count $process_count

#Getting Process Data 
process_data=$(hadoop fs -cat $adlpath$procdirpath/$FILENAME)
echo Process data $process_data

if [ $wrapper_directory/$JOBNAME.sh ]  #Checking for job availability
then
echo JOB PRESENT IN THE WRAPPERS
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_AVAILABILITY','JOB_AVAILABILITY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

#Executing the job
echo Job Starts.......
sh $wrapper_directory/$JOBNAME.sh

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
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_EXECUTION','JOB_PROCESS_CONTROL CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #JOB_PROCESS_CONTROL check
echo JOB FAILED

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_EXECUTION','JOB_PROCESS_CONTROL CHECK','FAILED','JOB_RUN_STATUS in JOB_PROCESS_CONTROL table is ${job_run_status}',SYSTIMESTAMP,'INBOUND');
exit;
EOF
fi  #JOB_PROCESS_CONTROL check


var=$(hadoop fs -ls $adlpath$completedirpath/$FILENAME)
if [ "$var" != "" ]  #File Availability in Complete Directory
then
echo FILE IS IN COMPLETE DIR

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_COMPLETE_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

#Getting Record count of the file in Complete Dir 
complete_count=$(hadoop fs -cat $adlpath$completedirpath/$FILENAME | wc -l)
echo Process Count $complete_count

#Getting Data from the file in Complete Dir
complete_data=$(hadoop fs -cat $adlpath$completedirpath/$FILENAME)
echo Process data $complete_data

#Comparing the record counts of the file in process directory and complete directory
if [ $process_count -eq $complete_count ]  #Record Count check in complete directory
then
echo COUNT MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','RECORD_COUNT_COMPLETE_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #Record Count check in complete directory
echo COUNT MISMATCH
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','RECORD_COUNT_COMPLETE_DIRECTORY','FAILED','Process Count is ${process_count} and Complete count is ${complete_count}',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #End of Record Count check in complete directory
#End of comparison between record counts of the file in process directory and complete directory

#Comaparing the data in the files available in the process directory and complete directory
if [ "$process_data" == "$complete_data" ]  #Data validation in complete directory
then
echo DATA MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','DATA_VALIDATION_COMPLETE_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #Data validation in complete directory
echo DATA MISMATCH
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','DATA_VALIDATION_COMPLETE_DIRECTORY','FAILED','Data mismatch between process and complete directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #Data validation in complete directory
#End of comparison between the data in the files available in the process directory and complete directory

else  #File Availability in Complete Directory
echo FILE IS NOT IN COMPLETE DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_COMPLETE_DIRECTORY','FAILED','File is not present in the complete directory path',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #File Availability in Complete Directory


job_run_id=$(echo $job_run_id | sed -e 's/[\r\n]//g')
today=`date +%Y%m%d`
#File availability check in conformed directory.
var=$(hadoop fs -ls $adlpath$cnfldirpath/create_date=$today/source_file_name=$FILENAME/$FILENAME"_"$job_run_id".avro")
if [ "$var" != "" ]  #File Availability in Conformed Directory
then
echo FILE IS IN CONFORMED DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_CONFORMED_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #File Availability in Conformed Directory
echo FILE IS NOT AVAILABLE IN THE CONFORMED DIRECTORY
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_CONFORMED_DIRECTORY','FAILED','File is not present in the conformed directory path',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #File Availability in Conformed Directory
#End of file availability check in conformed directory.



##################################################################
#Hive Validation

typeset -u colhead 
typeset -u line

var=$(hive -e "use governed_data; set hive.cli.print.header=true; select * from $HIVE_TABLE limit 0;")
var=${var//$HIVE_TABLE./}

colhead=$(echo $var | awk -F ' create_job_run_id' '{print $1}')
columnname=${colhead// /,}

file_count=$process_count
file_count=(`expr $file_count - 1`)
hive_count=$(hive -e "use governed_data; set hive.cli.print.header=true; set hive.compute.query.using.stats=false; select count(*) from $HIVE_TABLE where create_job_run_id = $job_run_id and source_file_name='$FILENAME';")

#Count comparison between process file and hive table
if [[ $file_count -eq $hive_count ]]
then
echo HIVE COUNT IS MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','HIVE_VALIDATION','RECORD_COUNT_VALIDATION','PASSED',SYSTIMESTAMP,'INBOUND');
exit;

else
echo HIVE COUNT IS NOT MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','HIVE_VALIDATION','RECORD_COUNT_VALIDATION','FAILED','Record count of the source is not matching with the hive data',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi
#End of Count comparison between process file and hive table

#Data comparison between process file and hive table
hive_data=$(hive -e "use governed_data; set hive.cli.print.header=true; select $columnname from $HIVE_TABLE where create_job_run_id = $job_run_id and source_file_name='$FILENAME';")
file_data=$process_data
file_data=$(echo "$file_data" | tr '","' ' ')
if [ "$hive_data" == "$file_data" ]
then
echo HIVE DATA IS MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','HIVE_VALIDATION','DATA_VALIDATION','PASSED',SYSTIMESTAMP,'INBOUND');
exit;

else
echo HIVE DATA IS NOT MATCHING
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','HIVE_VALIDATION','DATA_VALIDATION','FAILED','Data from the source file is not matching with the hive data',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi
#Data comparison between process file and hive table


#End of hive validation
##################################################################



#getting data from FILE_CONTROL table
file_processing_status=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT FILE_PROCESSING_STATUS FROM FILE_CONTROL WHERE FILE_NAME='$FILENAME';
exit;
EOF`
echo $file_processing_status


#FILE_CONTROL table check
if [ $file_processing_status = 3 ]  #File control check
then
echo FILE PROCESSING PASSED

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

elif [ $file_processing_status = 2 ]  #File control check
then
echo FILE IS MOVED TO ERROR

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','FAILED','File is moved to error directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #File control check
echo FILE PROCESSING FAILED

sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_CONTROL CHECK','FAILED','FILE_CONTROL table entry is ${file_processing_status}',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #File control check
#End of FILE_CONTROL table check

#ERROR Directory Check
var=$(hadoop fs -ls $adlpath$errdirpath/$FILENAME)
echo var: $var
if [ "$var" != "" ]  #File Availability in Error Directory
then
echo FILE IS IN ERROR DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_ERROR_DIRECTORY','FAILED','File is available in the error directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #File Availability in Error Directory
echo FILE IS NOT AVAILABLE IN THE ERROR DIRECTORY
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_ERROR_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #File Availability in Error Directory
#End of ERROR Directory Check

#ERROR_LOG check
err_code=`sqlplus -s $DB_CONNECTION <<EOF
set head off 
SELECT ERROR_CODE FROM ERROR_LOG WHERE JOB_RUN_ID=$job_run_id; 
exit;
EOF`

###############
echo ERROR_CODE: $err_code
#End of ERROR_LOG check


#REJECT Directory Check
var=$(hadoop fs -cat $adlpath$rejdirpath/$FILENAME/part* | wc -l)
echo var: $var
if [[ $var = 0 ]]  #File Availability in Reject Directory
then
echo FILE IS NOT AVAILABLE IN THE REJECT DIRECTORY
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_REJECT_DIRECTORY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #File Availability in Reject Directory
echo FILE IS IN REJECT DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','FILE_MOVEMENT','FILE_AVAILABILITY_REJECT_DIRECTORY','FAILED','File is available in the reject directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF
fi  #File Availability in Reject Directory
#End of REJECT Directory Check

else  #Check for valid JOB_RUN_ID
echo JOB_RUN_ID IS NOT CREATED

fi  #Check for valid JOB_RUN_ID

else  #Checking for job availability
echo JOB IS NOT AVAILABLE IN THE WRAPPERS
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','$JOB_AVAILABILITY','JOB_AVAILABILITY','FAILED','Job is not present in the wrappers directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #Checking for job availability

else  #File Availability in Process(If not Available)
echo FILE IS NOT IN PROCESS DIR
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','$FILE_AVAILABILITY','FILE_AVAILABILITY_PROCESS_DIRECTORY','FAILED','File is not present in the process directory',SYSTIMESTAMP,'INBOUND');
exit;
exit;
EOF

if [ $wrapper_directory/$JOBNAME.sh ]  #Checking for job availability(If the File is not available in the Process Dir)
then
echo JOB PRESENT IN THE WRAPPERS
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','JOB_AVAILABILITY','JOB_AVAILABILITY','PASSED',SYSTIMESTAMP,'INBOUND');
exit;
EOF

else  #Checking for job availability(If the File is not available in the Process Dir)
echo JOB IS NOT AVAILABLE IN THE WRAPPERS
sqlplus -s $DB_CONNECTION <<EOF
insert into process_owner_test_log(source_name,stage,interface_id,interface_name,interface_subtype,file_name,test_scenario,test_case,step_name,test_result,comments,execute_date,interface_type)
values('$SOURCENAME','PROCESS TO CONFORMED','$INTERFACEID','$INTERFACENAME','$SUBTYPE','$FILENAME','POSITIVE','$JOB_AVAILABILITY','JOB_AVAILABILITY','FAILED','Job is not present in the wrappers directory',SYSTIMESTAMP,'INBOUND');
exit;
EOF

fi  #Checking for job availability(If the File is not available in the Process Dir)



fi  #File Availability in Process Ends


fi  #Positive Scenario Ends

done  #End of Outer Loop