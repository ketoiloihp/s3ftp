FROM phusion/baseimage
ENV DEBIAN_FRONTEND=noninteractive

#add this for mustache templates in config files
ADD https://raw.githubusercontent.com/tests-always-included/mo/master/mo /usr/bin/
RUN chmod a+rx /usr/bin/mo

RUN apt-get update && \
    apt-get install -y gosu && \
    apt-get upgrade -y
    
RUN apt-get -y install --no-install-recommends \   
    automake \
    autotools-dev \
    g++ \
    git \
    libcurl4-gnutls-dev \
    libfuse-dev \
    libssl-dev \
    libxml2-dev \
    make \
    pkg-config \
    python3-pip \
    python3-setuptools \
    vsftpd \
    openssh-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Run commands to set-up everything
RUN pip3 install --upgrade pip wheel
RUN pip3 install awscli && \
  git clone https://github.com/s3fs-fuse/s3fs-fuse.git && \
  cd s3fs-fuse && \
  ./autogen.sh && \
  ./configure  && \
  make && \
  make install && \
  mkdir -p /home/aws/s3bucket/ && \
  echo "/usr/sbin/nologin" >> /etc/shells

ADD s3-fuse.sh /usr/local/

ADD vsftpd.conf /etc/vsftpd.conf

RUN chown root:root /etc/vsftpd.conf

ADD sshd_config /etc/ssh/sshd_config

ADD users.sh /usr/local/

ADD add_users_in_container.sh /usr/local/

RUN echo "/usr/sbin/nologin" >> /etc/shells

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# Copy needed config files to their destinations

# Expose ftp and sftp ports
EXPOSE 21 22

# Run supervisord at container start
CMD ["/usr/bin/supervisord"]
