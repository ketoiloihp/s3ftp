#!/bin/bash
# This script will update the env.list file (file containing USERS environrment variable) and add the new users if there are any.
# Will check for new users at a given time interval (change sleep duration on line 33)
FTP_USER_SUBFOLERS=${USER_SUBFOLERS:-"files"}
FTP_USER_SUBFOLERS_RW=${USER_SUBFOLERS_RW:-""}
FTP_USER_SUBFOLERS_RW=${USER_SUBFOLERS_RW:-$FTP_USER_SUBFOLERS}
FTP_USER_SUBFOLERS_R=${USER_SUBFOLERS_R:-""}
FTP_SUBFOLER_NAME=${FTP_SUBFOLER:-"ftp-users"}
FTP_DIRECTORY="/home/aws/s3bucket/${FTP_SUBFOLER_NAME}"

CONFIG_FILE="env.list" # May need to modify config file name to reflect future changes in env file location/name
SLEEP_DURATION=60
# Change theses next two variables to set different permissions for files/directories
# These were default from vsftpd so change accordingly if necessary
FILE_PERMISSIONS=644
DIRECTORY_PERMISSIONS=755

add_users() {
  aws s3 cp s3://$CONFIG_BUCKET/$CONFIG_FILE ~/$CONFIG_FILE
  USERS=$(cat ~/"$CONFIG_FILE" | grep USERS | cut -d '=' -f2)

  for u in $USERS; do
    read username passwd <<< $(echo $u | sed 's/:/ /g')

    # If account exists set password again 
    # In cases where password changes in env file
    if getent passwd "$username" >/dev/null 2>&1; then
      echo $u | chpasswd -e

      # Fix for issue when pulling files that were uploaded directly to S3 (through aws web console)
      # Permissions when uploaded directly through S3 Web client were set as:
      # 000 root:root
      # This would not allow ftp users to read the files
      for subfolder in $FTP_USER_SUBFOLERS; do
        # Search for files and directories not owned correctly
        if [ ! -z $ROOT_FOLDER ]; then
          find "$ROOT_FOLDER"/"$subfolder"/* \( \! -user "$username" \! -group "$username" \) -print0 | xargs -0 chown "$username:$username"

          # Search for files with incorrect permissions
          find "$ROOT_FOLDER"/"$subfolder"/* -type f \! -perm "$FILE_PERMISSIONS" -print0 | xargs -0 chmod "$FILE_PERMISSIONS"

          # Search for directories with incorrect permissions
          find "$ROOT_FOLDER"/$subfolder/* -type d \! -perm "$DIRECTORY_PERMISSIONS" -print0 | xargs -0 chmod "$DIRECTORY_PERMISSIONS"
        else
          find "$FTP_DIRECTORY"/"$username"/"$subfolder"/* \( \! -user "$username" \! -group "$username" \) -print0 | xargs -0 chown "$username:$username"

          # Search for files with incorrect permissions
          find "$FTP_DIRECTORY"/"$username"/"$subfolder"/* -type f \! -perm "$FILE_PERMISSIONS" -print0 | xargs -0 chmod "$FILE_PERMISSIONS"

          # Search for directories with incorrect permissions
          find "$FTP_DIRECTORY"/"$username"/$subfolder/* -type d \! -perm "$DIRECTORY_PERMISSIONS" -print0 | xargs -0 chmod "$DIRECTORY_PERMISSIONS"
        fi
      done

    fi

    # If user account doesn't exist create it 
    # As well as their home directory 
  if ! getent passwd "$username" >/dev/null 2>&1; then
      if [ -z $ROOT_FOLDER ]; then
        useradd -d "$FTP_DIRECTORY/$username" -s /usr/sbin/nologin $username
        usermod -G ftpaccess $username
  
        mkdir -p "$FTP_DIRECTORY/$username"
        chown root:ftpaccess "$FTP_DIRECTORY/$username"
        chmod 750 "$FTP_DIRECTORY/$username"
      else
        useradd -d "$ROOT_FOLDER" -s /usr/sbin/nologin $username
        echo "local_root=$ROOT_FOLDER" >> /etc/vsftpd_user_conf/$username
        chmod 750 "$ROOT_FOLDER"
      fi
      

    fi

    # create folder follow the structure
    for subfolder in $FTP_USER_SUBFOLERS; do
      if [ ! -z $ROOT_FOLDER ]; then
        mkdir -p $ROOT_FOLDER/$subfolder
        chmod 770 "$ROOT_FOLDER/$subfolder"
      else
        mkdir -p $FTP_DIRECTORY/$username/$subfolder
        chmod 750 "$FTP_DIRECTORY/$username/$subfolder"
      fi
      chown root:ftpaccess "$FTP_DIRECTORY/$username/$subfolder"
    done

    #enable write for some folder
    for subfolder in $FTP_USER_SUBFOLERS_RW; do
      if [ ! -z $ROOT_FOLDER ]; then
        mkdir -p $ROOT_FOLDER/$subfolder
        chmod 770 "$ROOT_FOLDER/$subfolder"
      else
        mkdir -p $FTP_DIRECTORY/$username/$subfolder
        chmod 750 "$FTP_DIRECTORY/$username/$subfolder"
      fi
      chown $username:ftpaccess "$FTP_DIRECTORY/$username/$subfolder"
    done

    for subfolder in $FTP_USER_SUBFOLERS_R; do
      if [ ! -z $ROOT_FOLDER ]; then
        mkdir -p $ROOT_FOLDER/$subfolder
      else
        mkdir -p $FTP_DIRECTORY/$username/$subfolder
      fi
      mkdir -p $FTP_DIRECTORY/$username/$subfolder
      chown root:ftpaccess "$FTP_DIRECTORY/$username/$subfolder"
      chmod 750 "$FTP_DIRECTORY/$username/$subfolder"
    done
  done
}

 while true; do
   add_users
   sleep $SLEEP_DURATION
 done
