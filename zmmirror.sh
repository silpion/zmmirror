#!/bin/bash
# This script uses the Zimbra update check service to download the latest
# release of the network edition.
# 
# The default is to download the file to a subdirectory of the directory
# this script is located in.  This can be changed by modifying the variable
# MIRROR_DIR below.
#
# The subdirectory will be named based on the platform the zimbra variant
# is built for.  The names were chosen to make them simple to use with
# puppet/facter.  The tarball will be saved under the original name in the
# target directory and an additional symlink with less information in the
# filename will be created as well, again to simplify the use of the mirror
# in combination with puppet.
#
# Change the variable PLATFORMS below to choose which platforms (aka operating
# systems) you want to download for.
# 
# Copyright (c) 2014 Malte Stretz <stretz@silpion.de> (Silpion IT-Solutions GmbH)
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
set -e -o pipefail

# The following config values can be overridden by creating a file
# zmmirror.conf next to this script.

# Change this to choose your destination operating systems.  Sane choices are:
# * redhat-6.5
# * ubuntu-10.04
# * ubuntu-12.04
# * ubuntu-14.04
# * sles-11
PLATFORMS="redhat-6.5 ubuntu-12.04"

# Change this to store the files somewhere else or change their owner.
MIRROR_DIR=$(dirname $0)
MIRROR_OWNER=$(id -u)
MIRROR_GROUP=$(id -g)
MIRROR_MOD=0755

# You probably don't want to change this.
LOCK_DIR=$MIRROR_DIR
LOCK_FILE=$LOCK_DIR/$(basename $0 .sh).lock

# You probably don't want to change this either.
UPDATE_URL=https://www.zimbra.com/aus/universal/update.php
DEFAULT_VERSION=8.0.0.5434

CONFIG_FILE=$(dirname $0)/$(basename $0 .sh).conf
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi


main() {
  # Create mirror directory if it doesn't exist yet
  install -d -m $MIRROR_MOD -o $MIRROR_OWNER -g $MIRROR_GROUP "$MIRROR_DIR"
  {
    # Try to acquire a lock, fail if not successful
    flock -n 9
    echo $$ >&9
    trap "rm -f '$LOCK_FILE'" EXIT
    (
      # We'll work in the mirror directory from here on
      cd "$MIRROR_DIR"

      # Download all the platforms!
      for platform in $PLATFORMS; do
        download $platform
      done
    )
  } 9>> "$LOCK_FILE"
}

download() {
  local platform=$1

  # Create the target directory if it doesn't exist yet
  install -d -m $MIRROR_MOD -o $MIRROR_OWNER -g $MIRROR_GROUP $platform

  # This file might/will contain the latest version mirrored
  local latestfile=$platform.latest
  if [ -f "$latestfile" ]; then
    latestversion=$(<$latestfile)
  else
    # Default to some older version
    latestversion=$DEFAULT_VERSION
  fi
  # Split the old version
  local majorversion=$(cut -d . -f 1 <<< $latestversion)
  local minorversion=$(cut -d . -f 2 <<< $latestversion)
  local microversion=$(cut -d . -f 3 <<< $latestversion)
  local buildversion=$(cut -d . -f 4 <<< $latestversion)

  # Determine the correct Zimbra platform identifier
  local platformos=$(cut -d - -f 1 <<< $platform)
  local platformversion=$(cut -d - -f 2 <<< $platform)
  local platformzm=${platformos^^[a-z]}
  case $platformzm in
    REDHAT|CENTOS)
      platformzm=RHEL
    ;;
    SUSE)
      platformzm=SLES
    ;;
  esac
  platformzm=${platformzm}${platformversion%.*}_64

  # Retrieve the update info XML file and parse it
  local urls=$(curl "${UPDATE_URL}?type=NETWORK&platform=${platformzm}&majorversion=${majorversion}&minorversion=${minorversion}&microversion=${microversion}&buildnum=${buildversion}" | \
    awk -F '[\t =]' '$1 == "<update" { for (i = 2; i < NF; i++) { if ($i == "updateURL") { print $(i+1) } } }' | sort | tr -d '"')

  # The XML file might have contained one or more URLs
  for url in $urls; do
    local version=$(basename "$url" | tr '_-' '[.*]' | cut -d . -f 3-5,7)
    local destfile=$platform/$(basename "$url")
    local destlink=$platform/zcs-ne-$version-$platform.tgz
    # Download the file
    echo Retrieving "$url"...
    curl -R "$url" -o "$destfile"
    # Create a nice symlink
    ln -s $(basename "$destfile") "$destlink"
    # Fix up the permissions
    chown "$MIRROR_OWNER:$MIRROR_GROUP" "$destfile" "$destlink"
    # Remember this version as the latest
    echo $version > $platform.latest
    echo Retrieved version $version for $platform
  done
}

curl() {
  # Be silent, follow redirects
  command curl -sS -L "$@"
}


main "$@"
exit


