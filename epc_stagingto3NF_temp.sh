BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
BASE_FOLDER_FUNCTIONLIBRARY="/home/sshuser/Test_Automation/FunctionLibrary"
BASE_FOLDER_SCRIPTS="/home/sshuser/Test_Automation/Scripts"
. $BASE_FOLDER/inbound_environment.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_epc_staging_3nf.sh

#NUM=$1

#Getting the sequence numbers
#SEQUENCE=`sqlplus -s $DB_CONNECTION <<EOF
#set head off feedback off
#SELECT A.SEQ_NO FROM TESTING_CONFIG A, TESTING_JOBS B WHERE A.SEQ_NO=B.SEQ_NO AND A.INTERFACE_ID='4.8.7' AND B.STAGE='PROCESS' ORDER BY A.SEQ_NO ASC;
#exit;
#EOF`

#echo SEQUENCE: $SEQUENCE

valid=0
SEQUENCE=$1
stagingto3nf $SEQUENCE

#echo SEQUENCE: $SEQUENCE
#arr=(`echo ${SEQUENCE}`); #Assigning sequence numbers to Array 
#echo "ArrCount: ${arr[@]}"
#for i in "${arr[@]}"
#do
#stagingto3nf $i
#if [ "$NUM" = "$i" ]
#then
#valid=1
#break
#fi

#done

#if [ $valid -eq 1 ]
#then
#echo VALID SEQUENCE
#echo "i: $i"
#Staging to 3NF
#stagingto3nf $i


#else
#echo INVALID SEQUENCE
#fi