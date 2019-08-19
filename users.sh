#!/bin/bash

FTP_SUBFOLER_NAME=${FTP_SUBFOLER:-"ftp-users"}
FTP_DIRECTORY="/home/aws/s3bucket/${FTP_SUBFOLER_NAME}"

# Create a group for ftp users
groupadd ftpaccess


# Create a directory where all ftp/sftp users home directories will go
mkdir -p $FTP_DIRECTORY
chown root:root $FTP_DIRECTORY
chmod 755 $FTP_DIRECTORY

# Expecing an environment variable called USERS to look like "bob:hashedbobspassword steve:hashedstevespassword"
for u in $USERS; do
  
  read username passwd <<< $(echo $u | sed 's/:/ /g')

  # User needs to be created every time since stopping the docker container gets rid of users.
  useradd -d "$FTP_DIRECTORY/$username" -s /usr/sbin/nologin $username
  usermod -G ftpaccess $username

  # set the users password
  echo $u | chpasswd -e
  
  if [ -z "$username" ] || [ -z "$passwd" ]; then
    echo "Invalid username:password combination '$u': please fix to create '$username'"
    continue
  elif [ -d "$FTP_DIRECTORY/$username" ]; then
    echo "Skipping creation of '$username' directory: already exists"

    # Directory exists but permissions for it have to be setup anyway.
    chown root:ftpaccess "$FTP_DIRECTORY/$username"
    chmod 750 "$FTP_DIRECTORY/$username"
    chown $username:ftpaccess "$FTP_DIRECTORY/$username/$FTP_USER_SUBFOLER"
    chmod 750 "$FTP_DIRECTORY/$username/$FTP_USER_SUBFOLER"
  else
    echo "Creating '$username' directory..."
    
    # Root must own all directories leading up to and including users home directory
    mkdir -p "$FTP_DIRECTORY/$username"
    chown root:ftpaccess "$FTP_DIRECTORY/$username"
    chmod 750 "$FTP_DIRECTORY/$username"
    
    # Need files sub-directory for SFTP chroot
    mkdir -p "$FTP_DIRECTORY/$username/$FTP_USER_SUBFOLER"
    chown $username:ftpaccess "$FTP_DIRECTORY/$username/$FTP_USER_SUBFOLER"
    chmod 750 "$FTP_DIRECTORY/$username/$FTP_USER_SUBFOLER"
  fi
  
done
