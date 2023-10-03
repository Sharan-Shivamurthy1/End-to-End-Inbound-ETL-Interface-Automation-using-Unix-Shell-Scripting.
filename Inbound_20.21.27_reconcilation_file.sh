#--------------------------
#Define the Enviroment Variables
#----------------------------------------
BASE_FOLDER="/home/sshuser/Test_Automation/ConfigFiles"
BASE_FOLDER_FUNCTIONLIBRARY="/home/sshuser/Test_Automation/FunctionLibrary"
. $BASE_FOLDER/inbound_environment.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_arrival_process.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_process_conformed.sh
. $BASE_FOLDER_FUNCTIONLIBRARY/inbound_conformed_staging.sh


PREFIX=Mediation_20-21-27
SEQUENCE=1

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


#Arrival To process
ArrivaltoProcess $FILENAME

echo FLAG_OUT: $FLAG

if [ $FLAG = 0 ]
then

#Process to Conformed
ProcesstoConformed $FILENAME

fi
done
#End of looping file processing