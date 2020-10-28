FROM ubuntu:18.04

ENV DEBIAN_FRONTEND noninteractive

ADD assets/ruby-2.6.5.sh /tmp/
RUN chmod +x /tmp/ruby-2.6.5.sh \
  && /tmp/ruby-2.6.5.sh

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
    ` # compilation dependency ` \
    build-essential cmake pkg-config \
    ` # libraries dependency ` \
    libssl1.1  zlib1g     libuv1     libwslay1 \
    libssl-dev zlib1g-dev libuv1-dev libwslay-dev \
    ` # git ` \
    git-core \
    ` # ssh ` \
    openssh-server \
    ` # supervisord ` \
    supervisor \
    ` # timezone and locale ` \
    tzdata locales \
  ` # ======================================================================================== ` \
  ` # setup locales ` \
  ` # ======================================================================================== ` \
  && echo 'LC_ALL="en_US.UTF-8"' >> /etc/environment \
  && echo 'LANG="en_US.UTF-8"'   >> /etc/environment \
  && echo 'LANGUAGE="en_US:en"'  >> /etc/environment \
  && sed -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -i /etc/locale.gen \
  && locale-gen \
  ` # ======================================================================================== ` \
  ` # setup openssh ` \
  ` # ======================================================================================== ` \
  && mkdir /var/run/sshd \
  ` # Define and allow root login through password ` \
  && echo 'root:THEPASSWORDYOUCREATED' | chpasswd \
  && sed -i 's/\#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
  ` # SSH port setup fix. ` \
  && sed -i 's/\#Port 22/Port 3268/' /etc/ssh/sshd_config \
  ` # SSH login fix. Otherwise user is kicked off after login ` \
  && sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd \
  ` # ======================================================================================== ` \
  ` # install h2o ` \
  ` # ======================================================================================== ` \
  && mkdir -p /tmp/h2o \
  && git clone https://github.com/h2o/h2o.git /tmp/h2o \
  && cd /tmp/h2o \
  && cmake . \
  && make \
  && make install \
  && rm -rf /tmp/h2o

  RUN ` # ======================================================================================== ` \
  ` # install cgit ` \
  ` # ======================================================================================== ` \
  && mkdir -p /tmp/cgit \
  && git clone https://git.zx2c4.com/cgit/ /tmp/cgit \
  && cd /tmp/cgit \
  && git submodule init \
  && git submodule update \
  ` # && echo 'CGIT_SCRIPT_PATH = /usr/local/share/cgit' >> cgit.conf ` \
  && make \
  && make install \
  ` # && ln -sf /usr/local/share/cgit/cgit.cgi /usr/local/bin/ ` \
  && cd /tmp \
  && rm -rf /tmp/cgit \
  ` # ======================================================================================== ` \
  ` # install gitolite ` \
  ` # ======================================================================================== ` \
  && useradd --create-home --shell /bin/bash git \
  && mkdir -p /home/git/gitolite \
  && mkdir -p /home/git/bin \
  && git clone https://github.com/sitaramc/gitolite /home/git/gitolite \
  && /home/git/gitolite/install -to /home/git/bin \
  && rm -rf /home/git/gitolite \
  ` # ======================================================================================== ` \
  ` # clean installation ` \
  ` # ======================================================================================== ` \
  && apt-get remove --purge -y build-essential cmake pkg-config libssl-dev zlib1g-dev libuv1-dev libwslay-dev \
  && apt-get autoremove --purge -y \
  && apt-get autoclean -y

# forward request and error logs to docker log collector
RUN mkdir -p /var/run/h2o/ \
  && touch /var/run/h2o/h2o.pid \
  && chown -Rv git.git /var/run/h2o/ \
  && mkdir -p /var/log/h2o/ \
  && ln -sf /dev/stdout /var/log/h2o/access.log \
  && ln -sf /dev/stderr /var/log/h2o/error.log

ADD assets/etc                   /etc
ADD assets/usr                   /usr
ADD assets/var                   /var
ADD assets/docker-entrypoint.sh  /

EXPOSE 3268 8080 8443
ENTRYPOINT ["/docker-entrypoint.sh"]