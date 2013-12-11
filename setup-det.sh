#!/bin/bash

##########################################################
# Set up Docker containers with basic dev tools and Elm  #
##########################################################

CONFIG_FILE=".detrc"
# For `make -j X`
#BUILD_JOBS=`grep '^processor\s*\:\s*[0-9][0-9]*$' /proc/cpuinfo | wc -l`

if [ `whoami` != "root" ]; then
  echo "Must run det as root"
  exit 1
fi

if [ -f $CONFIG_FILE ]; then
  source ./$CONFIG_FILE
else
  echo "You must have a ${CONFIG_FILE} in the current directory"
  exit 1
fi

if [ $# -gt 0 ] ; then
  ELM_VERSIONS=$*
  echo "Using Elm versions: ${ELM_VERSIONS}"
fi

if [ "X${ELM_VERSIONS}" == "X" ]; then
  echo "You must set up a ELM_VERSIONS list in your ${CONFIG_FILE}"
  exit 1
fi

# Simple setup function for a container:
#  setup_container(image id, base image, commands to run to set up)
setup_container() {
  local ID=$1
  local BASE=$2
  local RUN=$3

  # Does this image exist? If yes, ignore
  docker inspect "$ID" &> /dev/null
  if [[ $? -eq 0 ]]; then
    echo "Found existing container [$ID]"
    return
  fi

  # No such image, so make it
  echo "Did not find container container [$ID], creating..."
  docker run $BASE /bin/bash -c "$RUN"
  sleep 2
  docker commit `docker ps -l -q` $ID
}

# A basic dev image with the build tools needed for Elm
# adding "universe" to make it easier to add additional tools for
# builds that need it
setup_container "dev_base" "ubuntu:12.10" " \
  echo 'deb http://archive.ubuntu.com/ubuntu quantal main universe' > /etc/apt/sources.list; \
  apt-get update; \
  apt-get install -y haskell-platform git autoconf libtool make ncurses-dev g++ llvm libgmp3c2 wget; \
  cabal update; \
  cabal install alex happy; \
"

setup_container "dev_base_ghc7.6" "dev_base" " \
  cd /tmp && \
  wget http://www.haskell.org/ghc/dist/7.6.3/ghc-7.6.3-x86_64-unknown-linux.tar.bz2 && \
  wget http://www.haskell.org/platform/download/2013.2.0.0/haskell-platform-2013.2.0.0.tar.gz"

setup_container "dev_base_ghc7.6_2" "dev_base_ghc7.6" " \
  cd /tmp && \
  tar jxf ghc-7.6.3-x86_64-unknown-linux.tar.bz2 && \
  cd ghc-7.6.3 && \
  PATH=~/.cabal/bin:$PATH ./configure && \
  make;  \
  make install && \
  cd /tmp && \
  tar xzf haskell-platform-2013.2.0.0.tar.gz"

setup_container "dev_base_ghc76_2_platform" "dev_base_ghc7.6_2" " \
  cd /tmp && \
  cd haskell-platform-2013.2.0.0 && \
  PATH=~/.cabal/bin:$PATH ./configure && \
  make; \
  make install"

# The main Elm repo in an image by itself
setup_container "elm_dev" "dev_base_ghc76_2_platform" " \
  git clone https://github.com/evancz/Elm /usr/src/Elm/"

# For each version of Elm, make an image by checking out that branch
# on the repo, building it and installing it
for EV in $ELM_VERSIONS; do
  setup_container "elm_dev-$EV" "elm_dev" " \
    cd /usr/src/Elm && \
    git fetch origin && \
    git checkout $EV && \
    git pull origin $EV && \
    cabal update && \
    cabal install --only-dependencies && \
    cabal configure && \
    cabal build && \
    cabal install"
done
