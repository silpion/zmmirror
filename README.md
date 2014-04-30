zmmirror
========

Small script to mirror the latest version of Zimbra.

This script uses the Zimbra update check service to download the latest
release of the network edition.

The default is to download the file to a subdirectory of the directory
this script is located in.  This can be changed by modifying the variable
MIRROR_DIR in the script

The subdirectory will be named based on the platform the zimbra variant
is built for.  The names were chosen to make them simple to use with
puppet/facter.  The tarball will be saved under the original name in the
target directory and an additional symlink with less information in the
filename will be created as well, again to simplify the use of the mirror
in combination with puppet.
