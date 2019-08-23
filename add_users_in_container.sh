#!/bin/bash
# This script will update the env.list file (file containing USERS environrment variable) and add the new users if there are any.
# Will check for new users at a given time interval (change sleep duration on line 33)
FTP_USER_SUBFOLERS=${USER_SUBFOLERS:-"files"}
FTP_USER_SUBFOLERS_RW=${USER_SUBFOLERS_RW:-""}
FTP_USER_SUBFOLERS_RW=${USER_SUBFOLERS_RW:-$FTP_USER_SUBFOLERS}
FTP_USER_SUBFOLERS_R=${USER_SUBFOLERS_R:-""}
FTP_SUBFOLER_NAME=${FTP_SUBFOLER:-"ftp-users"}
FTP_DIRECTORY="/home/aws/s3bucket/${FTP_SUBFOLER_NAME}"
CHMOD_MASK=750

if [ ! -z "$FTP_LOCAL_MASH" ]; then
  CHMOD_MASK=$((777 - $(echo $FTP_LOCAL_MASH | sed 's/^0*//')))
fi

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
    read username passwd user_folder<<< $(echo $u | sed 's/:/ /g')

    USER_PATH="$ROOT_FOLDER"/"$username"
    if [ ! -z $ROOT_FOLDER ]; then
      USER_PATH="$ROOT_FOLDER"/"$user_folder"
    else
      USER_PATH="$ROOT_FOLDER"/"$user_folder"
    fi
    
    cat ~/"$CONFIG_FILE" | grep "SSH_PUBLIC_KEY=$username" | (while read SSH_KEY_TEXT; do
      SSH_PUBLIC_KEY=$(echo $SSH_KEY_TEXT | cut -d ':' -f2)

      mkdir -p "$USER_PATH"
      if [ ! -d "$USER_PATH"/.ssh ]; then
        cp /root/.ssh $USER_PATH -R
      fi
      cat $USER_PATH/.ssh/authorized_keys | grep "$SSH_PUBLIC_KEY" > /dev/null
      if [ "$?" != "0" ]; then
        echo "$SSH_PUBLIC_KEY" >> $USER_PATH/.ssh/authorized_keys
      fi
      chmod 600 $USER_PATH/.ssh/authorized_keys
      chown $username.$username $USER_PATH/.ssh -R
    done
      # If account exists set password again 
      # In cases where password changes in env file
      if getent passwd "$username" >/dev/null 2>&1; then
        if [ -z "$DISABLED_LOGIN_PWD" ]; then
          echo $u | chpasswd -e
        fi
        
        # Fix for issue when pulling files that were uploaded directly to S3 (through aws web console)
        # Permissions when uploaded directly through S3 Web client were set as:
        # 000 root:root
        # This would not allow ftp users to read the files
        for subfolder in $FTP_USER_SUBFOLERS; do
          # Search for files and directories not owned correctly
          find "$USER_PATH"/"$subfolder"/* \( \! -user "$username" \! -group "$username" \) -print0 | xargs -0 chown "$username:$username"

          # Search for files with incorrect permissions
          find "$USER_PATH"/"$subfolder"/* -type f \! -perm "$FILE_PERMISSIONS" -print0 | xargs -0 chmod "$FILE_PERMISSIONS"

          # Search for directories with incorrect permissions
          find "$USER_PATH"/$subfolder/* -type d \! -perm "$DIRECTORY_PERMISSIONS" -print0 | xargs -0 chmod "$DIRECTORY_PERMISSIONS"
        done
      fi

    # If user account doesn't exist create it 
    # As well as their home directory 
    if ! getent passwd "$username" >/dev/null 2>&1; then
      useradd -d "$USER_PATH" -s /usr/sbin/nologin $username
      usermod -G ftpaccess $username
      chown root:ftpaccess "$USER_PATH"
      chmod 750 "$USER_PATH"
    fi
    )

    # create folder follow the structure
    for subfolder in $FTP_USER_SUBFOLERS; do
      mkdir -p $USER_PATH/$subfolder
      chown $username:ftpaccess "$USER_PATH/$subfolder"
      chmod 750 "$USER_PATH/$subfolder"
    done

    # enable write for some folder
    for subfolder in $FTP_USER_SUBFOLERS_RW; do
      mkdir -p $USER_PATH/$subfolder
      chown $username:ftpaccess "$USER_PATH/$subfolder"
      chmod 750 "$USER_PATH/$subfolder"
    done

    for subfolder in $FTP_USER_SUBFOLERS_R; do
      mkdir -p $USER_PATH/$subfolder
      chown root:ftpaccess "$USER_PATH/$subfolder"
      chmod 750 "$USER_PATH/$subfolder"
    done
  done
}

 while true; do
   add_users
   sleep $SLEEP_DURATION
 done
