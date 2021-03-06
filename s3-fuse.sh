#!/bin/bash

FTP_SUBFOLER_NAME=${FTP_SUBFOLER:-"ftp-users"}
IAM_ROLE=${IAM_ROLE:-"auto"}
AWS_REGION=${AWS_REGION:-"ap-southeast-1"}
# create a link folder if the link is change
# if [ "$FTP_SUBFOLER_NAME" != "ftp-users" ]; then
#   echo "secure_chroot_dir=/home/aws/s3bucket/$FTP_SUBFOLER_NAME" >> /etc/vsftpd.conf
# fi

# save template for rewrite when have new config
if [ ! -f "/etc/vsftpd.conf.example" ]; then
  cp /etc/vsftpd.conf /etc/vsftpd.conf.example
fi
cat /etc/vsftpd.conf.example > /etc/vsftpd.conf
if [ ! -f "/etc/ssh/sshd_config.example" ]; then
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.example
fi
cat /etc/ssh/sshd_config.example > /etc/ssh/sshd_config
# this option using for vsftpd only
if [ ! -z "$FTP_DENIED_PERMISSION" ]; then
  cat /etc/vsftpd.conf | grep "cmds_denied=$FTP_DENIED_PERMISSION" > /dev/null
  if [ "$?" != "0" ]; then
    echo "cmds_denied=$FTP_DENIED_PERMISSION" >> /etc/vsftpd.conf
  fi
fi

# modify unmask by env
if [ ! -z "$FTP_LOCAL_MASH" ]; then
  CHMOD_MASK=$((777 - $(echo $FTP_LOCAL_MASH | sed 's/^0*//')))
  cat /etc/vsftpd.conf | grep "chown_upload_mode=$CHMOD_MASK" > /dev/null
  if [ "$?" != "0" ]; then
    echo "local_umask=$FTP_LOCAL_MASH" >> /etc/vsftpd.conf
    echo "file_open_mode=$CHMOD_MASK" >> /etc/vsftpd.conf
    echo "chown_upload_mode=$CHMOD_MASK" >> /etc/vsftpd.conf
  fi
else
  cat /etc/vsftpd.conf | grep "local_umask=022" > /dev/null
  if [ "$?" != "0" ]; then
    echo "local_umask=022" >> /etc/vsftpd.conf
  fi
fi

# set sftp mode to allow: read, upload, read & write
ENABLE_PWD_AUTH=yes
if [ ! -z "$DISABLED_LOGIN_PWD" ]; then
  ENABLE_PWD_AUTH=no
fi
if [ "$SFTP_MODE" == "r" ]; then
  # read only
  cat /etc/ssh/sshd_config | grep "Match Group ftpaccess" > /dev/null
  if [ "$?" != "0" ]; then
cat <<EOT >> /etc/ssh/sshd_config
Match Group ftpaccess
    PasswordAuthentication $ENABLE_PWD_AUTH
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    PermitTunnel no
    AllowAgentForwarding no
    ForceCommand internal-sftp -R
EOT
  fi

elif [ "$SFTP_MODE" == "u" ]; then
  #upload only
  cat /etc/ssh/sshd_config | grep "Match Group ftpaccess" > /dev/null
  if [ "$?" != "0" ]; then
cat <<EOT >> /etc/ssh/sshd_config
Match Group ftpaccess
    PasswordAuthentication $ENABLE_PWD_AUTH
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    PermitTunnel no
    AllowAgentForwarding no
    ForceCommand internal-sftp -u 0222 -P rename,remove,rmdir,setstat,fsetstat
EOT
  fi

else
  # normal rw
  cat /etc/ssh/sshd_config | grep "Match Group ftpaccess" > /dev/null
  if [ "$?" != "0" ]; then
cat <<EOT >> /etc/ssh/sshd_config
Match Group ftpaccess
    PasswordAuthentication $ENABLE_PWD_AUTH
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    ForceCommand internal-sftp
EOT
  fi

fi
service ssh restart

# disabled chmod on vsftp
if [ ! -z "$FTP_DISABLED_CHMOD" ]; then
  cat /etc/vsftpd.conf | grep "chmod_enable=NO" > /dev/null
  if [ "$?" != "0" ]; then
    echo "chmod_enable=NO" >> /etc/vsftpd.conf
  fi
fi

# set a custom path default for ftp
PATH_ROOT=/home/aws/s3bucket/ftp-users
if [ ! -z $ROOT_FOLDER ]; then
  PATH_ROOT=$ROOT_FOLDER
fi
cat /etc/vsftpd.conf | grep "secure_chroot_dir=$PATH_ROOT"
if [ "$?" != "0" ]; then
  echo "secure_chroot_dir=$PATH_ROOT" >> /etc/vsftpd.conf
fi

# Check first if the required FTP_BUCKET variable was provided, if not, abort.
if [ -z $FTP_BUCKET ]; then
  echo "You need to set BUCKET environment variable. Aborting!"
  exit 1
fi

# Then check if there is an IAM_ROLE provided, if not, check if the AWS credentials were provided.
if [ -z $IAM_ROLE ]; then
  echo "You did not set an IAM_ROLE environment variable. Checking if AWS access keys where provided ..."
fi

# Abort if the AWS_ACCESS_KEY_ID was not provided if an IAM_ROLE was not provided neither.
if [ -z $IAM_ROLE ] &&  [ -z $AWS_ACCESS_KEY_ID ]; then
  echo "You need to set AWS_ACCESS_KEY_ID environment variable. Aborting!"
  exit 1
fi

# Abort if the AWS_SECRET_ACCESS_KEY was not provided if an IAM_ROLE was not provided neither. 
if [ -z $IAM_ROLE ] && [ -z $AWS_SECRET_ACCESS_KEY ]; then
  echo "You need to set AWS_SECRET_ACCESS_KEY environment variable. Aborting!"
  exit 1
fi

# If there is no IAM_ROLE but the AWS credentials were provided, then set them as the s3fs credentials.
if [ -z $IAM_ROLE ] && [ ! -z $AWS_ACCESS_KEY_ID ] && [ ! -z $AWS_SECRET_ACCESS_KEY ]; then
  #set the aws access credentials from environment variables
  echo $AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY > ~/.passwd-s3fs
  chmod 600 ~/.passwd-s3fs
fi

# Update the vsftpd.conf file to include the IP address if running on an EC2 instance
if curl -s http://instance-data.ec2.internal > /dev/null ; then
  IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  sed -i "s/^pasv_address=/pasv_address=$IP/" /etc/vsftpd.conf
else
  echo "Not Running on ec2"
  #exit 1
fi

# start s3 fuse
# Code above is not needed if the IAM role is attaced to EC2 instance 
# s3fs provides the iam_role option to grab those credentials automatically
/usr/local/bin/s3fs $FTP_BUCKET /home/aws/s3bucket -o allow_other -o mp_umask="0022" -o iam_role="$IAM_ROLE" -o url=https://s3-$AWS_REGION.amazonaws.com #-d -d -f -o f2 -o curldbg
/usr/local/users.sh
FTPGROUPID=`getent group ftpaccess | awk -F: '{printf "%d\n", $3}'`
umount -l /home/aws/s3bucket

#remount s3 folder to assign permission for the ftpaccess group 
/usr/local/bin/s3fs $FTP_BUCKET /home/aws/s3bucket -o allow_other,gid=$FTPGROUPID,use_rrs=1 -o mp_umask="0022" -o iam_role="$IAM_ROLE" -o url=https://s3-$AWS_REGION.amazonaws.com
