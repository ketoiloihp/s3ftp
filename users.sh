#!/bin/bash

FTP_USER_SUBFOLERS=${USER_SUBFOLERS:-"files"}
FTP_SUBFOLER_NAME=${FTP_SUBFOLER:-"ftp-users"}
FTP_DIRECTORY="/home/aws/s3bucket/${FTP_SUBFOLER_NAME}"

# Create a group for ftp users
groupadd ftpaccess


# Create a directory where all ftp/sftp users home directories will go
mkdir -p $FTP_DIRECTORY
chown root:root $FTP_DIRECTORY
chmod 755 $FTP_DIRECTORY
CHMOD_MASK=750

if [ ! -z "$FTP_LOCAL_MASH" ]; then
  CHMOD_MASK=$((777 - $(echo $FTP_LOCAL_MASH | sed 's/^0*//')))
fi

# Expecing an environment variable called USERS to look like "bob:hashedbobspassword steve:hashedstevespassword"
for u in $USERS; do
  
  read username passwd user_folder<<< $(echo $u | sed 's/:/ /g')

  USER_PATH="$ROOT_FOLDER"/"$username"
  if [ ! -z $ROOT_FOLDER ]; then
    USER_PATH="$ROOT_FOLDER"/"$user_folder"
  else
    USER_PATH="$ROOT_FOLDER"/"$user_folder"
  fi

  # User needs to be created every time since stopping the docker container gets rid of users.
  useradd -d "$USER_PATH" -s /usr/sbin/nologin $username
  usermod -G ftpaccess $username

  # set the users password
  echo $u | chpasswd -e
  
  if [ -z "$username" ] || [ -z "$passwd" ]; then
    echo "Invalid username:password combination '$u': please fix to create '$username'"
    continue
  elif [[ -d "$USER_PATH" ]]; then
    echo "Skipping creation of '$username' directory: already exists"

    # Directory exists but permissions for it have to be setup anyway.
    chown root:ftpaccess "$USER_PATH"
    chmod 750 "$USER_PATH"
    for subfolder in $FTP_USER_SUBFOLERS; do
      chown $username:ftpaccess "$USER_PATH/$subfolder"
      chmod 750 "$USER_PATH/$subfolder"
    done
  else
    echo "Creating '$username' directory..."
    
    # Root must own all directories leading up to and including users home directory
    chown root:ftpaccess "$USER_PATH"
    chmod 750 "$USER_PATH"

    # Need files sub-directory for SFTP chroot
    for subfolder in $FTP_USER_SUBFOLERS; do
      mkdir -p "$USER_PATH/$subfolder"
      chown $username:ftpaccess "$USER_PATH/$subfolder"
      chmod 750 "$USER_PATH/$subfolder"
    done
  fi
done
