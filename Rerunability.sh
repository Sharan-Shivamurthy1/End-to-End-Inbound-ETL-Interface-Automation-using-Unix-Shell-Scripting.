BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
BASE_FOLDER_FUNCTIONLIBRARY="/home/sshuser/Test_Automation/FunctionLibrary"
. $BASE_FOLDER/KafkaEnvironmentVariables.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/Functions.sh

#SQLConnection DW_STAGING Testing123 10.71.000.6 0000 rdwdev CAMPAIGN
echo $count
currentdate=`date +%y/%m/%d-%H:%M:%S`

#Get All the Job ID at all the stages
INTERFACE='Kafka'

for (( StageCounter=1; StageCounter<=3; StageCounter=StageCounter+1 ))
do
case "$StageCounter" in
   "1") STAGE='CONFORM'
        TARGET_STAGE='BDCD'
        #DB=$STGDB_CONNECTION
        if [ "$INTERFACE" = 'Kafka' ]
        then
          SEQ_NUM[0]=42
          InterfaceType='Type2'
          ColumnNames='*'
        fi
   ;;
   "2") STAGE='STAGING'
        TARGET_STAGE='DW_STAGING'
        DB=$STGDB_CONNECTION
        if [ "$INTERFACE" = 'Kafka' ]
        then
        echo "Inside If"
          SEQ_NUM[0]=42
          InterfaceType='Type1'
          ColumnNames='*'
        fi
   ;;
   "3") STAGE='3NF'
        TARGET_STAGE='DW_3NF'
        DB=$TNFDB_CONNECTION
        if [ "$INTERFACE" = 'ERP' ]
        then
        echo "Inside If"
          SEQ_NUM[0]=42
          InterfaceType='Type1'
          ColumnNames='*'
        fi
   ;;
esac

echo "Seq=${#SEQ_NUM[@]}"


#Get all the job names at all stages
for (( SeqCounter=0; SeqCounter<${#SEQ_NUM[@]}; SeqCounter=SeqCounter+1 ))
do
  echo "Get All the Job ID at all the stages"
  
  #Get job ID
  GetJobName ${SEQ_NUM[SeqCounter]} $STAGE
  stringarray=($var)
    for (( TableNameCounter=0; TableNameCounter<${#stringarray[@]}; TableNameCounter=TableNameCounter+1 ))
    do
      GetTableName ${stringarray[TableNameCounter]}
      TableName[TableNameCounter]=$TABLE_NAME
      
      #Get target Object ID
      GetTargetObjectID ${TableName[TableNameCounter]} $TARGET_STAGE
      TargetObjectID=$TARGET_OBJECT_ID

      #Get Job Run ID
      GetJobRunID ${stringarray[TableNameCounter]} $currentdate
      SuccessJobRunID=$SUCCESS_JOB_RUN_ID
      
      #Get Max Source Job Run ID
      GetMaxSourceJobRunID $SuccessJobRunID
      MaxSrcJobRunID=$MAX_SRC_JOB_RUN_ID
      
      #Get Max Current Job Run ID
      GetMaxCurrentJobRunID $TargetObjectID $MaxSrcJobRunID
      MaxCurrentJobRunID=$MAX_JOB_RUN_ID_CURRENT
      echo "AMax=$MaxCurrentJobRunID"
      
      #Get Min Current Job Run ID
      GetMinCurrentJobRunID $TargetObjectID $MaxSrcJobRunID
      MinCurrentJobRunID=$MIN_JOB_RUN_ID_CURRENT
      echo "AMin=$MinCurrentJobRunID"

if [ "$StageCounter" != '1' ]
then
ExpDataCount=`sqlplus -s $DB << EOF
set head off 
select count(*) from ${TableName[TableNameCounter]} where create_job_run_id BETWEEN $MinCurrentJobRunID and $MaxCurrentJobRunID;
exit;
EOF`
echo "Exp Count=$ExpDataCount"

ExpData=`sqlplus -s $DB << EOF
set head off 
select $ColumnNames from ${TableName[TableNameCounter]} where create_job_run_id BETWEEN $MinCurrentJobRunID and $MaxCurrentJobRunID;
exit;
EOF`
echo "Data=$ExpData"
fi
    #Update the reprocess flag
    UpdateReprocessFlag $MinCurrentJobRunID $MaxCurrentJobRunID
    
    #Run the job
    sh $wrapper_directory/${stringarray[TableNameCounter]}.sh
     
    #Get new job run ID
    GetJobRunID ${stringarray[TableNameCounter]} $currentdate
    NewSuccessJobRunID=$SUCCESS_JOB_RUN_ID

case "$InterfaceType" in
  "Type1")
  #Validate if old job run ID still exists and new job run id is in update job run id field
  ;;
  "Type2")
  #Validate if old job run ID doesn't exists and new job run id is created
  ;;
esac
if [ "$StageCounter" != 1 ]
then   
NewDataCount=`sqlplus -s $DB << EOF
set head off 
select count(*) from $SourceTableName where create_job_run_id=$NewSuccessJobRunID;
exit;
EOF`
echo "Data Count=$NewDataCount"

NewData=`sqlplus -s $DB << EOF
set head off 
select * from $SourceTableName where create_job_run_id=$NewSuccessJobRunID;
exit;
EOF`
echo "Data=$NewData"

  if [ "$NewDataCount" -eq '0' ]
  then
   echo "Data not present-pass"
  else
    echo "Data present-fail"
  fi
  
  if [ -z "$NewData" ]
  then
   echo "Data not present-pass"
  else
    echo "Data present-fail"
  fi   
fi
    done    #end of Table counter loop
done    #end of sequence counter loop

done  #end of stage loop