#!/bin/bash

set -ex

RUBY_MAJOR="2.6"
RUBY_VERSION="2.6.5"
RUBY_DOWNLOAD_SHA256="66976b716ecc1fd34f9b7c3c2b07bbd37631815377a2e3e85a5b194cfdcbed7d"

# skip installing gem documentation
mkdir -p /usr/local/etc 
cat >> /usr/local/etc/gemrc <<GEMRC
# Read about the gemrc format at http://docs.rubygems.org/read/chapter/11

# Print backtrace when RubyGems encounters an error
backtrace: true

# --user-install is used to install to $HOME/.gem/ by default since we want to separate
#                pacman installed gems and gem installed gems
# gem: --user-install --no-ri --no-rdoc --no-document
GEMRC

{ 
  echo 'install: --no-document'; 
  echo 'update: --no-document'; 
} >> /usr/local/etc/gemrc

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
buildDeps=' dpkg-dev libbz2-dev libglib2.0-dev libncurses-dev ruby wget xz-utils '
apt-get update 
apt-get install -y autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm5 libgdbm-dev
apt-get install -y --no-install-recommends $buildDeps 
rm -rf /var/lib/apt/lists/* 

wget -O ruby.tar.gz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.gz"
echo "${RUBY_DOWNLOAD_SHA256} *ruby.tar.gz" | sha256sum -c -
mkdir -p /usr/src/ruby 
tar -zxvf ruby.tar.gz -C /usr/src/ruby --strip-components=1
rm ruby.tar.gz 

cd /usr/src/ruby 

# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
{ 
  echo '#define ENABLE_PATH_CHECK 0'; 
  echo; 
  cat file.c; 
} > file.c.new 
mv file.c.new file.c 
    
autoconf 
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" 
./configure --build="$gnuArch" \
            --disable-install-doc \
            --enable-shared
            
make -j "$(nproc)" 
make install 

dpkg-query --show --showformat '${package}\n' \
    | grep -P '^libreadline\d+$' \
    | xargs apt-mark manual
apt-get purge -y --auto-remove $buildDeps 
cd / 
rm -r /usr/src/ruby 

# rough smoke test
ruby --version && gem --version && bundle --version

rm -rfv /tmp/ruby-*