#--------------------------
#Define the Enviroment Variables
#--------------------------
BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
BASE_FOLDER_FUNCTIONLIBRARY="/home/sshuser/Test_Automation/FunctionLibrary"
. $BASE_FOLDER/inbound_environment.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_ArrivalToProcess.sh


PREFIX=Campaign_CHCMFT011_Metadata
SEQUENCE=1

#sh /home/sshuser/Test_Automation/Scripts/inbound_arrival_process.sh $PREFIX
ArrivalToProcess $PREFIX
if [ FLAG = 1 ]
then
exit
fi


sh /home/sshuser/Test_Automation/Scripts/inbound_process_conformed.sh $SEQUENCE

if [ FLAG = 1 ]
then
exit
fi

sh /home/sshuser/Test_Automation/Scripts/inbound_conformed_staging.sh $SEQUENCE


#--------------------------
#Arrival To process
#--------------------------


#--------------------------
#Process to Conform
#--------------------------
