#!/bin/sh
#
# STOR2RRD install script
# usage: ./install.sh
#


LANG=C
export LANG

if [ ! "$1"x = "x" ]; then
  if [ "$1" = "wrap" ]; then
    # create a package, internall usage only
    ver=`grep "version=" dist_storage/etc/stor2rrd.cfg|sed 's/version=//g'`
    if [ "$ver"x = "x" ]; then
      echo "Something is wroing, cannot find the version"
      exit 1
    fi
    if [ -f stor2rrd.tar.Z ]; then
      echo "removing stor2rrd.tar.Z"
      rm stor2rrd.tar.Z
    fi
    if [ -f stor2rrd.tar ]; then
      echo "removing stor2rrd.tar"
      rm stor2rrd.tar
    fi
    tar cvf stor2rrd.tar dist_storage
    compress stor2rrd.tar
    if [ -f stor2rrd.tar.Z ]; then
      echo "removing dist"
      rm -r dist_storage
    fi
    echo ""
    echo "$ver has been created"
    echo ""
    exit
  fi
fi

# test if "ed" command does not exist, it might happen especially on some Linux distros
ed << END 2>/dev/null 1>&2
q
END
if [ $? -gt 0 ]; then
  echo "ERROR: "ed" command does not seem to be installed or in $PATH"
  echo "Exiting ..."
  exit 1
fi

umask 0022 
ID=`id -un`

echo "STOR2RRD installation under user: \"$ID\""
echo " make sure it is realy the user which should own it"
echo ""
HOME1="$HOME/stor2rrd"
if [ -f "$HOME/.stor2rrd_home" ]; then
  HOME1=`cat "$HOME/.stor2rrd_home"`
fi
echo "Where STOR2RRD will be installed [$HOME1]:"
read HOMELPAR

if [ "$HOMELPAR"x = "x" ]; then
    HOMELPAR="$HOME1"
fi

if [ -f $HOMELPAR/bin/storage.pl ]; then
  echo "STOR2RRD instance already exists there, use update.sh script for the update"
  exit 0
fi

echo "What user will be used for storage access: [$ID]"
read id_new

if [ ! "$id_new"x = "x" ]; then
   id=$id_new 
fi

if [ "$HOMELPAR"x = "x" ]; then
  HOMELPAR=$HOME/stor2rrd
fi

if [ ! -d "$HOMELPAR" ]; then
  echo "Creating $HOMELPAR"
  mkdir "$HOMELPAR"
  if [ ! $? -eq 0 ]; then
    echo "Error during creation of $HOMELPAR, exiting ..."
    exit 0
  fi
fi

if [ -f stor2rrd.tar.Z ]; then
  which uncompress >/dev/null 2>&1 
  if [ $? -eq 0 ]; then 
     uncompress -f stor2rrd.tar.Z 
  else 
     which gunzip >/dev/null 2>&1 
     if [ $? -eq 0 ]; then 
       gunzip -f stor2rrd.tar.Z 
     else 
       echo "Could not locate uncompress or gunzip commands. exiting" 
       exit 
     fi 
  fi 
fi

chown $ID $HOMELPAR 
if [ ! $? -eq 0 ]; then
  echo "Problem with ownership of $HOMELPAR"
  echo "Fix it and run it again : chown  $ID $HOMELPAR"
  exit 0
fi


tar xf stor2rrd.tar
mv dist_storage/* $HOMELPAR/

chown -R $ID $HOMELPAR 2>&1| egrep -v "lost+found"
chmod 755 $HOMELPAR
chmod 666 $HOMELPAR/logs/error.log
chmod 755 $HOMELPAR/data
chmod 755 $HOMELPAR/www
chmod 755 $HOMELPAR/bin
chmod 755 $HOMELPAR/etc
chmod 755 $HOMELPAR/logs
if [ ! -d $HOMELPAR/tmp ]; then
  mkdir $HOMELPAR/tmp
fi
chmod 755 $HOMELPAR/tmp
chmod -R 755 $HOMELPAR/html # must be due tue subdirs jquery, images ...
chmod -R 755 $HOMELPAR/stor2rrd-cgi
chmod -R o+r $HOMELPAR/data
chmod -R o+x $HOMELPAR/data
chmod -R o+r $HOMELPAR/www
chmod -R o+x $HOMELPAR/www
chmod 755 $HOMELPAR/bin/*.pl
chmod 755 $HOMELPAR/bin/*.pm
chmod 755 $HOMELPAR/bin/*.sh
chmod 755 $HOMELPAR/*.sh
chmod 644 $HOMELPAR/etc/*
if [ ! -h $HOMELPAR/logs/error-cgi.log ]; then
  ln -s /var/tmp/stor2rrd-realt-error.log $HOMELPAR/logs/error-cgi.log
fi


rrd=`whereis rrdtool|awk '{print $2}'|wc -w`
if [ $rrd -eq 0 ]; then
  echo ""
  echo "Warning: RRDTool has not been found in \$PATH, placing /opt/freeware/bin/rrdtool"
  echo "         assure it is ok, if not then edit $HOMELPAR/etc/stor2rrd.cfg and change it"
  echo ""
  rrd="/opt/freeware/bin/rrdtool"
else
  rrd=`whereis rrdtool|awk '{print $2}'`
fi

per=`whereis perl|awk '{print $2}'|wc -w`
if [ $per -eq 0 ]; then
  echo ""
  echo "Warning: Perl has not been found in \$PATH, placing /usr/bin/perl"
  echo "         assure it is ok, if not then edit $HOMELPAR/etc/stor2rrd.cfg and change it"
  echo ""
  per="/usr/bin/perl"
else
  per=`whereis perl|awk '{print $2}'`
fi

# replace path for actual one in config files


HOMELPAR_slash=`echo $HOMELPAR|sed 's/\//\\\\\\//g'`
HOME_slash=`echo $HOME|sed 's/\//\\\\\\//g'`
rrd_slash=`echo $rrd|sed 's/\//\\\\\\//g'`
per_slash=`echo $per|sed 's/\//\\\\\\//g'`
# add actual paths
PERL5LIB=/opt/freeware/lib/perl/5.8.8:/opt/freeware/lib/perl/5.8.0:/usr/opt/perl5/lib/site_perl/5.8.2:/usr/lib/perl5/vendor_perl/5.8.5:/usr/share/perl5:/usr/lib/perl5
PPATH="/usr/lib64/perl5/vendor_perl
/opt/freeware/lib/perl
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/usr/lib64/perl5/vendor_perl"

perl_version=`$per -e 'print "$]\n"'|sed -e 's/0/\./g' -e 's/\.\.\.\./\./g' -e 's/\.\.\./\./g' -e 's/\.\./\./g' -e 's/ //g'`
PLIB=`for ppath in $PPATH
do
  echo $PERL5LIB|grep "$ppath/$perl_version"  >/dev/null
  if [ ! $? -eq 0 ]; then
    echo "$ppath/$perl_version"
   fi
done|xargs|sed 's/ /:/g'`
perl5lib_slash=`echo "$PLIB:$PERL5LIB"|sed -e 's/\//\\\\\\//g'`

 
echo "Configuring $HOMELPAR/etc/stor2rrd.cfg" 
ed $HOMELPAR/etc/stor2rrd.cfg << EOF 2>/dev/null 1>&2
g/__STOR2RRD_HOME__/s/__STOR2RRD_HOME__/$HOMELPAR_slash/g
g/__USER_HOME__/s/__USER_HOME__/$HOME_slash/g
g/__USER__/s/__USER__/$ID/g
g/__STOR2RRD_USER__/s/__STOR2RRD_USER__/$ID/g
g/__RRDTOOL__/s/__RRDTOOL__/$rrd_slash/g
g/__PERL__/s/__PERL__/$per_slash/g
g/__PERL5LIB__/s/__PERL5LIB__/$perl5lib_slash/g
w
q
EOF
if [ ! $? -eq 0 ]; then
  echo ""
  echo "Error!"
  echo "Probably does not exist command: \"ed\" "
  echo "If it is the case then install ed, \"rm -r $HOMELPAR\" and run install once more"
  echo "Or customization of $HOMELPAR/etc/lpar2rrd.cfg failed"
  echo "Contact support in this case"
  exit 0
fi


cd $HOMELPAR

# change #!bin/ksh in shell script to #!bin/bash on Linux platform
os_aix=` uname -a|grep AIX|wc -l`
if [ $os_aix -eq 0 ]; then
  # If Linux then change all "#!bin/sh --> #!bin/bash
  for sh in $HOMELPAR/bin/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/scripts/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/stor2rrd-cgi/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done
fi

#echo ""
#echo "Custom groups config file creation"
#$HOMELPAR/scripts/update_cfg_custom-groups.sh update

#echo ""
#echo "Favourites config file creation"
#$HOMELPAR/scripts/update_cfg_favourites.sh update

#echo ""
#echo "Alerting config file creation"
#$HOMELPAR/scripts/update_cfg_alert.sh update

# Check web user has read&executable rights for CGI dir stor2rrd-cgi
dir=`echo "$HOMELPAR/www"|sed 's/\\\//g'`
DIR=""
IFS_ORG=$IFS
IFS="/"
for i in $dir
do
  IFS=$IFS_ORG
  NEW_DIR=`echo $DIR$i/`
  #echo "01 $NEW_DIR -- $i -- $DIR ++ $www"
  NUM=`ls -dLl $NEW_DIR |awk '{print $1}'|sed -e 's/d//g' -e 's/-//g' -e 's/w//g' -e 's/\.//g'| wc -c`
  #echo "02 $NUM"
  if [ ! $NUM -eq 7 ]; then
    echo ""
    echo "WARNING, directory : $NEW_DIR has probably wrong rights"
    echo "         $www dir and its subdirs have to be executable&readable for WEB user"
    ls -lLd $NEW_DIR
    echo ""
  fi
  DIR=`echo "$NEW_DIR/"`
  #echo $DIR
  IFS="/"
done
IFS=$IFS_ORG


# ulimit check
# necessary for big aggregated graphs
#
# AIX:
# chuser  data=2097152 stor2rrd (1GB)
# chuser  stack=1048576 stor2rrd (512MB)

ulimit_message=0
data=`ulimit -d`
if [ ! "$data" = "unlimited" -a ! "$data" = "hard" -a ! "$data" = "soft" ]; then
  echo ""
  echo "Warning: increase data ulimit for $ID user, it is actually too low ($data)"
  echo " AIX: chuser  data=-1 $ID"
  echo " Linux: # vi /etc/security/limits.conf"
  echo "        @$ID        soft    data            -1"
  ulimit_message=1
fi
stack=`ulimit -s`
if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
  echo ""
  echo "Warning: increase stack ulimit for $ID user, it is actually too low ($stack)"
  echo " AIX: chuser  stack=-1 $ID"
  echo " Linux: # vi /etc/security/limits.conf"
  echo "        @$ID        soft    stack           -1"
  ulimit_message=1
fi
stack=`ulimit -m`
if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
  echo ""
  echo "Warning: increase stack ulimit for $ID user, it is actually too low ($rss)"
  echo " AIX: chuser  rss=-1 $ID"
  ulimit_message=1
fi
if [ $ulimit_message -eq 1 ]; then
  echo ""
  echo "Assure that the same limits has even web user (apache/nobody/http)"
  echo ""
fi


cd $HOMELPAR
if [ $os_aix -eq 0 ]; then
  free=`df .|grep -iv filesystem|xargs|awk '{print $4}'`
  freemb=`echo "$free/1048"|bc`
  if [ $freemb -lt 4048 ]; then
    echo ""
    echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
    echo "         note that 1 storage needs 2 - 4 GB space depends on number of volumes/pools/ranks/disks/mdisks"
  fi
else
  free=`df .|grep -iv filesystem|xargs|awk '{print $3}'`
  freemb=`echo "$free/2048"|bc`
  if [ $freemb -lt 4048 ]; then
    echo ""
    echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
    echo "         note that 1 storage needs 2 - 4 GB space depends on number of volumes/pools/ranks/disks/mdisks"
  fi
fi

# setting up the font dir (necessary for 1.3 on AIX)
FN_PATH="<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
<fontconfig>
<dir>/opt/freeware/share/fonts/dejavu</dir>
</fontconfig>"

if [ ! -f "$HOME/.config/fontconfig/.fonts.conf" -o `grep -i deja "$HOME/.config/fontconfig/.fonts.conf" 2>/dev/null|wc -l` -eq 0 ]; then
  if [ ! -d "$HOME/.config" ]; then
    mkdir "$HOME/.config"
  fi
  if [ ! -d "$HOME/.config/fontconfig" ]; then
    mkdir "$HOME/.config/fontconfig"
  fi
  echo $FN_PATH > "$HOME/.config/fontconfig/.fonts.conf"
fi
chmod 644 "$HOME/.config/fontconfig/.fonts.conf"
# no, no, it issues this error:
# Fontconfig warning: "/opt/freeware/etc/fonts/conf.d/50-user.conf", line 9: reading configurations from ~/.fonts.conf is deprecated.
#if [ ! -f "$HOME/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOME/.fonts.conf"
#  chmod 644 "$HOME/.fonts.conf"
#fi


# for web server user home
if [ ! -d "$HOMELPAR/tmp/home" ]; then
  mkdir "$HOMELPAR/tmp/home"
fi
#if [ ! -f "$HOMELPAR/tmp/home/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOMELPAR/tmp/home/.fonts.conf"
#fi
if [ ! -d "$HOMELPAR/tmp/home/.config" ]; then
  mkdir "$HOMELPAR/tmp/home/.config"
fi
if [ ! -d "$HOMELPAR/tmp/home/.config/fontconfig" ]; then
  mkdir "$HOMELPAR/tmp/home/.config/fontconfig"
fi
if [ ! -f "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf" ]; then
  echo $FN_PATH > "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"
fi
chmod 755 "$HOMELPAR/tmp/home"
chmod 755 "$HOMELPAR/tmp/home/.config"
chmod 755 "$HOMELPAR/tmp/home/.config/fontconfig"
chmod 644 "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"

# Checking installed Perl modules
cd $HOMELPAR
. etc/stor2rrd.cfg; $PERL bin/perl_modules_check.pl $PERL
echo ""
cd - >/dev/null

# RRDTool version checking for graph zooming
$rrd|grep graphv >/dev/null 2>&1
if [ $? -eq 1 ]; then
  # suggest RRDTool upgrade
  rrd_version=`$rrd -v|head -1|awk '{print $2}'`
  echo "Condider RRDtool upgrade to version 1.3.5+ (actual one is $rrd_version)"
  echo "This will allow graph zooming: http://www.stor2rrd.com/zoom.html"
  echo ""
fi

os_linux=`uname -a|grep Linux|wc -l`
if [ $os_linux -gt 0 ]; then
  # LinuxSE warning
  SELINUX=`ps -ef | grep -i selinux| grep -v grep|wc -l`

  if [ "$SELINUX" -gt 0  ]; then
    GETENFORCE=`getenforce 2>/dev/null`
    if [ "$GETENFORCE" = "Enforcing" ]; then
      echo ""
      echo "Warning!!!!!"
      echo "SELINUX status is Enforcing, it might cause a problem during Apache setup"
      echo "like this in Apache error_log: (13)Permission denied: access to /XXXX denied"
      echo ""
    fi
  fi
fi

# comment out LIBPATH on AIX to avoid including /opt/freeware/bin which can cause a problem in some situations
ed $HOMELPAR/etc/stor2rrd.cfg << EOF 2>/dev/null 1>&2
g/export LIBPATH=/s/export LIBPATH=/#export LIBPATH=/g
g/  LIBPATH=/s/  LIBPATH=/ #LIBPATH=/g
w
q
EOF



echo ""
echo "Installation has finished"
echo "Follow detailed installation instructions at :"
echo "  http://www.stor2rrd.com/install.htm"

echo "$HOMELPAR" > $HOME/.stor2rrd_home 2>/dev/null

