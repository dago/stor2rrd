#!/bin/ksh
#set -x

PATH=$PATH:/usr/bin:/bin
export PATH
umask 0022

if [ ! -d $WEBDIR ]; then
   echo "WEBDIR does not exist, supply it as the first parametr"
   exit 1
fi
if [ ! -d $INPUTDIR ]; then
   echo "Source does not exist, supply it as the second parametr"
   exit 1
fi
if [ ! -f $PERL ]; then
   echo "perl path is invalid, correct it and re-run the tool"
   exit 1
fi


type_amenu="A" # aggregated items under subsystem menu
type_lmenu="L" # item under subsystem
type_removed="R"
type_gmenu="G" # global menu
type_cmenu="C" # custom group menu
type_fmenu="F" # favourites menu
type_smenu="S" # subsystem menu
type_tmenu="T" # tail menu
type_hmenu="H" # storage menu
type_version="O" # free(open)/full version (1/0)

gmenu_created=0


if [ "$TMPDIR_STOR"x = "x" ]; then
  TMPDIR_STOR="$INPUTDIR/tmp"
fi
MENU_OUT=$TMPDIR_STOR/menu.txt-tmp
MENU_OUT_FINAL=$TMPDIR_STOR/menu.txt
rm -f $MENU_OUT



ALIAS_CFG="$INPUTDIR/etc/alias.cfg"
ALIAS=0
CGI_DIR="stor2rrd-cgi"
AGG_LIST="sum_io sum_data io_rate data_rate sum_capacity real used read_io write_io read write cache_hit r_cache_hit w_cache_hit r_cache_usage w_cache_usage resp resp_t resp_t_r resp_t_w  read_io_b write_io_b read_b write_b resp_t_b resp_t_r_b resp_t_w_b sys compress tier0 tier1 tier2 pprc_rio pprc_wio pprc_data_r pprc_data_w pprc_rt_r pprc_rt_w read_pct top"
SUBSYSTEM_LIST="POOL RANK MDISK VOLUME DRIVE PORT CPU-NODE HOST"
# avoid CPU-CORE on purpose
if [ -L "$INPUTDIR/data/$hmc/MDISK" ]; then 
  # SVC
  FIRST_GLOBAL="sum_io"
  FIRST_GLOBAL_SUB="MDISK"
  #FIRST="sum_data" # POOL, RANK
  #FIRST_SECOND="data_rate" # PORT
else
  # DS8K
  FIRST_GLOBAL="sum_io"
  FIRST_GLOBAL_SUB="RANK"
  #FIRST="read" # POOL, RANK
  #FIRST_SECOND="data_rate" # PORT
fi
TMPDIR_STOR=$INPUTDIR/tmp
INDEX=$INPUTDIR/html
pwd=`pwd`
TIME=`$PERL -e '$v = time(); print "$v\n"'`

if [ "$ACCOUTING"x = "x" ]; then
  ACCOUTING=0
fi

if [ $DEBUG ]; then echo "installing WWW : install-html.sh "; fi
if [ $DEBUG ]; then echo "Host identif   : $UNAME "; fi

if [ -f $BINDIR/premium.sh ]; then
  . $BINDIR/premium.sh
fi

if [ -f "$ALIAS_CFG" ]; then 
  ALIAS=1
fi

# create skeleton of menu
menu () {
  a_type=$1
  a_hmc=`echo "$2"|sed 's/:/===double-col===/g'`
  a_server=`echo "$3"|sed 's/:/===double-col===/g'`
  a_lpar=`echo "$4"|sed 's/:/===double-col===/g'`
  a_text=`echo "$5"|sed 's/:/===double-col===/g'`
  a_url=`echo "$6"|sed -e 's/:/===double-col===/g' -e 's/ /%20/g'`
  a_lpar_wpar=`echo "$7"|sed 's/:/===double-col===/g'` # lpar name when wpar is passing
  a_last_time=$8


  #if [ ! "$LPARS_EXCLUDE"x = "x" -a `echo "$4"|egrep "$LPARS_EXCLUDE"|wc -l` -eq 1 ]; then
  #  # excluding some LPARs based on a string : LPARS_EXCLUDE --> etc/.magic
  #  echo "lpar exclude   : $2:$2:$4 - exclude string: $LPARS_EXCLUDE"
  #  return 1
  #fi

  if [ "$a_type" = "$type_gmenu" -a $gmenu_created -eq 1 ]; then
    return # print global menu once
  fi

  echo "$a_type:$a_hmc:$a_server:$a_lpar:$a_text:$a_url:$a_lpar_wpar:$a_last_time" >> $MENU_OUT

}

#
# real start of the script
#

menu "$type_version" "0" "" "" "" "" ""

if [ $UPGRADE -eq 0 ]; then
  if [ ! -f $TMPDIR_STOR/$version-run ]; then
    if [ $DEBUG -eq 1 ]; then echo "Apparently nothing new, install_html.sh exiting"; fi
    exit 0
  else
    if [ $DEBUG -eq 1 ]; then echo "Apparently some changes in the env, install_html.sh continuing"; fi
  fi
else
  if [ $DEBUG -eq 1 ]; then echo "Looks like there was an upgrade, re-newing web pages"; fi
  touch $TMPDIR_STOR/$version
fi
rm -f $TMPDIR_STOR/$version-run

cp "$INPUTDIR/html/not_implemented.html" "$WEBDIR/" 

if [ ! -f "$WEBDIR/gui-help.html" ]; then
  # copy of help file
  cp "$INPUTDIR/html/gui-help.html" "$WEBDIR/" 
fi
if [ $UPGRADE -eq 1 ]; then
  cp "$INPUTDIR/html/gui-help.html" "$WEBDIR/"
fi


if [ $UPGRADE -eq 1 -o ! -f "$WEBDIR/hist_reports.html" -o ! -f $INPUTDIR/html/noscript.html -o ! -f $INPUTDIR/html/wipecookies.html -o ! -f "$WEBDIR/index.html" -o ! -f "$WEBDIR/gui-help.html" -o ! -f "$WEBDIR/hist_reports.html" -o ! -f "$WEBDIR/dashboard.html" ]; then
  cp "$INPUTDIR/html/dashboard.html" "$WEBDIR/"
  cp "$INPUTDIR/html/gui-help.html" "$WEBDIR/"
  cp "$INPUTDIR/html/index.html" "$WEBDIR/"
  cp "$INPUTDIR/html/wipecookies.html" "$WEBDIR/"
  cp "$INPUTDIR/html/noscript.html" "$WEBDIR/"
  cp "$INPUTDIR/html/hist_reports.html" "$WEBDIR/"
  cp "$INPUTDIR/html/test.html" "$WEBDIR/"
  cp "$INPUTDIR/html/robots.txt" "$WEBDIR/"
  cp "$INPUTDIR/html/favicon.ico" "$WEBDIR/"
fi

if [ ! -d "$WEBDIR/jquery" -o $UPGRADE -eq 1 -o ! -d "$WEBDIR/css" ]; then
  cd $INPUTDIR/html
  tar cf - jquery | (cd $WEBDIR ; tar xf - )
  cd - >/dev/null
fi

if [ ! -d "$WEBDIR/css" -o $UPGRADE -eq 1 ]; then
  cd $INPUTDIR/html
  tar cf - css | (cd $WEBDIR ; tar xf - )
  cd - >/dev/null
fi


#
# Main section
#

# create the index page with a pointer to the first HMC and the first managed name
# not nice code as necessary to use a temp file, it needs to be re-writen with awk to avoid it
TMP=/var/tmp/stor2rrd.$$
FLIST=`for m in $INPUTDIR/data/*/*; do echo "$m"|sed 's/ /====spacce====/g'; done|sort -fr|xargs -n 1024`
for m in $FLIST
do 
  continue # skip old GUI tree creation

  msys=`basename "$m"`
  m_space=`echo "$m"|sed 's/====spacce====/ /g'`
  msys_all=`dirname "$m_space"`
  hmc=`basename "$msys_all"`

  configured=`egrep "^$hmc:" $INPUTDIR/etc/storage-list.cfg|sed 's/^ *//g'|wc -l`
  if [ $configured -eq 0 ]; then
    # already unconfigured, then skip it
    continue
  fi

  # exclude sym links 
  if [ -L "$INPUTDIR/data/$msys" ]; then
    continue
  fi
  if [ ! -d "$WEBDIR/$hmc/$msys" ]; then
    continue
  fi
  echo "$hmc/$msys"
done|sort -f|head -1 > $TMP

# find out first HMC
first_hmc=`cat $TMP`
msys=`basename "$first_hmc"`
hmc=`dirname "$first_hmc"`
#rm -f $TMP

# workaround for sorting 
HLIST=`for m in $INPUTDIR/data/*; do echo "$m"|sed 's/ /====spacce====/g'; done|sort -fr|xargs -n 1024`
for dir1 in $HLIST
do

  # workaround for managed names with a space inside
  dir1_space=`echo "$dir1"|sed 's/====spacce====/ /g'`
  hmc=`basename "$dir1_space"`
  # exclude sym links 
  if [ -L "$dir1" ]; then
    continue
  fi

  if [ ! -d "$dir1" ]; then
    continue
  fi

  configured=`egrep "^$hmc:" $INPUTDIR/etc/storage-list.cfg|sed 's/^ *//g'|wc -l`
  if [ $configured -eq 0 ]; then
    # already unconfigured, then skip it
    continue
  fi

  st_type="DS8K"
  if [ -f "$INPUTDIR/data/$hmc/SWIZ" ]; then
    st_type="SWIZ"
  fi
  if [ -f "$INPUTDIR/data/$hmc/XIV" ]; then
    st_type="XIV"
  fi
  if [ -f "$INPUTDIR/data/$hmc/DS5K" ]; then
    st_type="DS5K"
  fi


  if [ $gmenu_created -eq 0 ]; then
    if [ $ACCOUTING -eq 1 ]; then # accounting for DHL
      menu "$type_gmenu" "accounting" "Accounting" "/stor2rrd-cgi/acc.sh?sort=server"
    fi
    gmenu_created=1 # it will not print global menu items
  fi
  menu "$type_hmenu" "$hmc" 
  menu "$type_hmenu" "$hmc" "Configuration" "$hmc/gui-config-detail.html"
  #menu "$type_hmenu" "$hmc" "Historical reports" "hist_reports.html"

  # Historical report form are different per each storage type
  hreport_form="hist_reports-$st_type.html"
  if [ ! -f "$INPUTDIR/html/$hreport_form" ]; then
    hreport_form="hist_reports.html"
  fi
  if [ "$st_type" = "DS5K" ]; then
    hreport_form="hist_reports-$st_type-v1.html"
    if [ -f "$INPUTDIR/data/$hmc/DS5K-v2" ]; then
      hreport_form="hist_reports-$st_type-v2.html"
    fi
  fi
  menu "$type_hmenu" "$hmc" "Historical reports" "$hreport_form"
  if [ $UPGRADE -eq 1 -o ! -f "$WEBDIR/$hreport_form" ]; then
    cp "$INPUTDIR/html/$hreport_form" "$WEBDIR"
  fi



  for subs in $SUBSYSTEM_LIST
  do
    cd $INPUTDIR/data/"$hmc" 

    if [ ! -d "$subs" -o -L "$subs" ]; then
      continue
    fi


    # workaround for managed names with a space inside
    #dir2_space=`echo "$dir2"|sed 's/====spacce====/ /g'`
    #managedname=`basename "$dir2_space"`
    managedname=$subs

    if [ "$managedname" = "iostats" -o "$managedname" = "tmp" ]; then
      continue
    fi

    if [ `echo "$SUBSYSTEM_LIST" | egrep " $managedname|$managedname "|wc -l` -eq 0 ]; then
      continue
    fi

    #cd  "$WEBDIR/$hmc/$managedname"

    if [ -f "$INPUTDIR/data/$hmc/SWIZ"  -a "$managedname" = "RANK" ]; then 
      # for SWIZ
      managedname_head="Managed&nbsp;disk"
    else
      managedname_head=$managedname
    fi

    if [ "$managedname" = "CPU-NODE" ]; then 
      managedname_head="CPU&nbsp;util"
    fi
    if [ "$managedname" = "NODE-CACHE" ]; then 
      managedname_head="Node&nbsp;Cache"
      continue # --> not implemented yet
    fi


    drive_exist=`ls -l $INPUTDIR/data/$hmc/DRIVE/*rr* 2>/dev/null|wc -l`

    # workaround for sorting 
    # here must be a list with predefined sorting and then check if it exist
    for managed1base in $SUBSYSTEM_LIST
    do
      if [ ! -d "../$managed1base" -o -L "../$managed1base" ]; then
        continue # exclude other stuff
      fi

      managed1base_head=$managed1base
      if [ -f "$INPUTDIR/data/$hmc/SWIZ" -a "$managed1base" = "RANK" ]; then 
        # for SWIZ
        managed1base_head="Managed&nbsp;disk"
      fi
      if [ "$managed1base" = "DRIVE" -a $drive_exist -eq 0 ]; then 
        continue  # SVC and DS8k do not have DRIVES stats
      fi
      if [ "$managed1base" = "CPU-NODE" ]; then 
        managed1base_head="CPU&nbsp;util"
      fi
      if [ "$managed1base" = "NODE-CACHE" ]; then 
        managed1base_head="Node&nbsp;Cache"
        continue # --> not implemented yet
      fi
    done

    if [ "$managedname" = "DRIVE" -a $drive_exist -eq 0 ]; then 
      continue  # SVC and DS8k do not have DRIVES stats
    fi

    if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_smenu : $hmc $managedname_head"; fi
    menu "$type_smenu" "$hmc" "$managedname_head" 

    c_io=0
    c_data=0
    c_resp=0
    c_capacity=0
    c_cache=0
    c_sys=0
    c_pprc=0
    c_top=0

    for lpar in $AGG_LIST
    do
      if [ "$managedname" = "HOST" ]; then  
        break # HOST does not have aggregates
      fi
      item_sum="sum"
      if [ -f "$TMPDIR_STOR/$hmc/$managedname-$lpar-d.cmd" ]; then
        if [ "$lpar" = "resp" -o "$lpar" = "resp_t" -o "$lpar" = "resp_t_r" -o "$lpar" = "resp_t_w" -o "$lpar" = "resp_t_r_b" -o "$lpar" = "resp_t_w_b" ]; then
          if [ $c_resp -gt 0 ]; then  
            continue
          fi
          (( c_resp = c_resp + 1 ))
          lpar_name="Response time"
          lpar="resp"
        fi
        if [ "$lpar" = "sum_io" -o "$lpar" = "io" -o "$lpar" = "io_rate" -o "$lpar" = "read_io" -o "$lpar" = "write_io" -o "$lpar" = "read_io_b" -o "$lpar" = "write_io_b" ]; then
          if [ $c_io -gt 0 ]; then  
            continue
          fi
          (( c_io = c_io + 1 ))
          lpar_name="IO"  
          lpar="io"
        fi
        if [ "$lpar" = "sum_data" -o "$lpar" = "data" -o "$lpar" = "data_rate" -o "$lpar" = "read" -o "$lpar" = "write" -o "$lpar" = "read_b" -o "$lpar" = "write_b" ]; then
          if [ $c_data -gt 0 ]; then  
            continue
          fi
          (( c_data = c_data + 1 ))
          lpar_name="Data"
          lpar="data"
        fi
        if [ "$lpar" = "sys" -o "$lpar" = "compress" ]; then
          if [ $c_sys -gt 0 ]; then  
            continue
          fi
          (( c_sys = c_sys + 1 ))
          lpar_name="CPU"
          lpar="cpu"
        fi
        if [ "$lpar" = "sum_capacity" -o "$lpar" = "used" -o "$lpar" = "real" -o "$lpar" = "tier0" -o "$lpar" = "tier2" -o "$lpar" = "tier1" ]; then
          if [ $c_capacity -gt 0 ]; then  
            continue
          fi
          (( c_capacity = c_capacity + 1 ))
          lpar_name="Capacity"
          lpar="cap"
        fi
        if [ "$lpar" = "cache_hit" -o "$lpar" = "read_pct" -o "$lpar" = "r_cache_usage" -o "$lpar" = "w_cache_usage" -o "$lpar" = "r_cache_hit" -o "$lpar" = "w_cache_hit" ]; then
          if [ $c_cache -gt 0 ]; then  
            continue
          fi
          (( c_cache = c_cache + 1 ))
          lpar_name="Cache"
          lpar="cache"
        fi
        if [ "$lpar" = "pprc_rio" -o "$lpar" = "pprc_wio" -o "$lpar" = "pprc_data_r" -o "$lpar" = "pprc_data_w" -o "$lpar" = "pprc_rt_r" -o "$lpar" = "pprc_rt_w" ]; then
          if [ $c_pprc -gt 0 ]; then  
            continue
          fi
          (( c_pprc = c_pprc + 1 ))
          lpar_name="PPRC"
          lpar="pprc"
        fi
        if [ "$lpar" = "top" ]; then
          if [ $c_top  -gt 0 ]; then  
            continue
          fi
          (( c_top  = c_top  + 1 ))
          lpar_name="Top"
          lpar="top"
          item_sum="all"
        fi
        menu "$type_amenu" "$hmc" "$managedname_head" "$lpar" "$lpar_name" "/stor2rrd-cgi/detail.sh?host=$hmc&type=$managedname&name=$lpar&storage=$st_type&item=$item_sum&gui=1&none=none"
      fi   
    done

    managed1base_head=$managedname 
    if [ -f "$INPUTDIR/data/$hmc/SWIZ" -a "$managedname" = "RANK" ]; then 
      # for SWIZ
      managed1base_head="Managed&nbsp;disk"
    fi
    if [ "$managedname" = "CPU-NODE" ]; then 
      managed1base_head="CPU&nbsp;util"
    fi
    if [ "$managedname" = "NODE-CACHE" ]; then 
      managed1base_head="Node&nbsp;Cache"
    fi

    #
    # Hosts
    if [ "$managedname" = "HOST" -a -f "$INPUTDIR/data/$hmc/HOST/hosts.cfg" ]; then
      for host_space in `cut -f1 -d ":" "$INPUTDIR/data/$hmc/HOST/hosts.cfg"| sed -e 's/ $//' -e 's/ /+===============+/g'| sort -fn `
      do
        host=`echo "$host_space" | sed 's/+===============+/ /g'`
        host_url=`$PERL -e '$s=shift;$s=~s/ /+/g;;$s=~s/([^A-Za-z0-9\+-])/sprintf("%%%02X",ord($1))/seg;print "$s\n";' "$host"`
        if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_amenu : $hmc:$managedname:$host_url - $host"; fi
        menu "$type_amenu" "$hmc" "$managed1base_head" "$host" "$host" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$host_url&storage=$st_type&item=host&gui=1&none=none"
      done
    fi


    #
    # Volumes
    if [ "$managedname" = "VOLUME" ]; then
     # special loop per volumes as there will not be volumes in menu just volumes grouped per nicks
     if [ ! -f "$INPUTDIR/data/$hmc/$managedname/volumes.cfg" ]; then
        if [ $DEBUG -eq 1 ]; then echo "volume no exist: $hmc:$managedname:$INPUTDIR/data/$hmc/$managedname/volumes.cfg "; fi
        continue # volumes stats do not exist there, at least cfg file
     fi
     for ii_space in `awk -F: '{print $1}' "$INPUTDIR/data/$hmc/$managedname/volumes.cfg"|sed -e 's/ $//' -e 's/ /+===============+/g'| sort -fn `
     do
       ii=`echo "$ii_space" | sed 's/+===============+/ /g'`
       ii_url=`$PERL -e '$s=shift;$s=~s/ /+/g;;$s=~s/([^A-Za-z0-9\+-])/sprintf("%%%02X",ord($1))/seg;print "$s\n";' "$ii"`
       al=`egrep "^$managedname:$hmc:$ii:" $ALIAS_CFG 2>/dev/null|awk -F: '{print $4}'`
       if [ ! "$al"x =  "x" ]; then
         if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_lmenu : $hmc:$managedname:$ii_url - $ii - alias: $al"; fi
         menu "$type_lmenu" "$hmc" "$managed1base_head" "$ii" "$al" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$ii_url&storage=$st_type&item=lpar&gui=1&none=none"
       else
         if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_lmenu : $hmc:$managedname:$ii_url - $ii"; fi
         menu "$type_lmenu" "$hmc" "$managed1base_head" "$ii" "$ii" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$ii_url&storage=$st_type&item=lpar&gui=1&none=none"
       fi
     done

    else

      #
      # POOLs
      if [ "$managedname" = "POOL" ]; then
        pwd=`pwd`
        if [ "$st_type" = "XIV" -o "$st_type" = "DS5K" ]; then
          cd  $INPUTDIR/data/$hmc/VOLUME # XIV has pools in Volumes
        else 
          cd  $INPUTDIR/data/$hmc/RANK
        fi

        for i in `find . -print |egrep "\.rrd$"|sed -e 's/\.\///g' -e 's/\.rrd//' -e 's/^.*-P//g'|sort -fn|uniq`
        do
         menu_type_def="$type_lmenu" 
         cd $pwd
           if [ $ALIAS -eq 1 ]; then
             al=`egrep "^$managedname:$hmc:$i:" $ALIAS_CFG|awk -F: '{print $4}'`
             #echo "003: $managedname:$hmc:$i: - $al"
             if [ ! "$al"x =  "x" ]; then
               if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_lmenu : $hmc:$managedname:$i - alias: $al"; fi
               menu "$type_lmenu" "$hmc" "$managed1base_head" "$i" "$al" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$i&storage=$st_type&item=lpar&gui=1&none=none"
             else 
               name=$i
               # translate index into name
               if [ -f "$INPUTDIR/data/$hmc/pool.cfg" ]; then
                 name=`egrep "^$i:" "$INPUTDIR/data/$hmc/pool.cfg"|awk -F: '{print $2}'`
                 if [ "$name"x = "x" ]; then
                   # name has not been found --> looks like an old POOL
	           name="$i"
                   menu_type_def="$type_removed" # place into removed menu
                 fi
               fi
               if [ $DEBUG -eq 1 ]; then echo "adding to menu : $menu_type_def : $hmc:$managedname:$i - $name"; fi
               menu "$menu_type_def" "$hmc" "$managed1base_head" "$i" "$name" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$i&storage=$st_type&item=lpar&gui=1&none=none"
             fi
           else
             name=$i
             # translate index into name
             if [ -f "$INPUTDIR/data/$hmc/pool.cfg" ]; then
               name=`egrep "^$i:" "$INPUTDIR/data/$hmc/pool.cfg"|awk -F: '{print $2}'`
               if [ "$name"x = "x" ]; then
                 # name has not been found --> looks like an old POOL
	         name="$i"
                 menu_type_def="$type_removed" # place into removed menu
               fi
             fi
             if [ $DEBUG -eq 1 ]; then echo "adding to menu : $menu_type_def : $hmc:$managedname:$i "; fi
             menu "$menu_type_def" "$hmc" "$managed1base_head" "$i" "$name" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$i&storage=$st_type&item=lpar&gui=1&none=none"
           fi
        done
      else

        #
        # everything rest as PORT, RANKs, .... 
        pwd=`pwd`
        cd  $INPUTDIR/data/$hmc/$managedname
        for ii in `find . -print |egrep "\.rrd$"|sed -e 's/\.\///g' -e 's/\.rrd//'|sort -fn`
        do
         menu_type_def="$type_lmenu" 
         cd $pwd
         if [ "$managedname" = "RANK" ]; then 
           i_pool=`echo $ii|grep -- "-P"|wc -l`
           if [ $i_pool -eq 0 ]; then
             next # it is something worng, could not found pool name
           fi
         fi
         i=`echo $ii|sed 's/-P.*//'` # filter pool info for Ranks 
           if [ $ALIAS -eq 1 ]; then
             al=`egrep "^$managedname:$hmc:$i:" $ALIAS_CFG|awk -F: '{print $4}'`
             #echo "003: $managedname:$hmc:$i: - $al"
             if [ ! "$al"x =  "x" ]; then
               if [ $DEBUG -eq 1 ]; then echo "adding to menu : $type_lmenu : $hmc:$managedname:$ii - $i - alias: $al"; fi
               menu "$type_lmenu" "$hmc" "$managed1base_head" "$ii" "$al" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$ii&storage=$st_type&item=lpar&gui=1&none=none"
             else 
               name=$i
               # translate index into name for MDISK
               if [ -f "$INPUTDIR/data/$hmc/mdisk.cfg" -a $managedname = "RANK" ]; then
                 name=`egrep "^$i:" "$INPUTDIR/data/$hmc/mdisk.cfg"|awk -F: '{print $2}'`
                 if [ "$name"x = "x" ]; then
                   # name has not been found --> looks like an old RANK
	           name="$i"
                   menu_type_def="$type_removed" # place into removed menu
                 fi
               fi
               if [ $DEBUG -eq 1 ]; then echo "adding to menu : $menu_type_def : $hmc:$managedname:$ii - $i - $name"; fi
               menu "$menu_type_def" "$hmc" "$managed1base_head" "$ii" "$name" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$ii&storage=$st_type&item=lpar&gui=1&none=none"
             fi
           else
             name=$i
             # translate index into name for MDISK
             if [ -f "$INPUTDIR/data/$hmc/mdisk.cfg" -a $managedname = "RANK" ]; then
               name=`egrep "^$i:" "$INPUTDIR/data/$hmc/mdisk.cfg"|awk -F: '{print $2}'`
               if [ "$name"x = "x" ]; then
                 # name has not been found --> looks like an old RANK
	         name="$i"
                 menu_type_def="$type_removed" # place into removed menu
               fi
             fi
             if [ $DEBUG -eq 1 ]; then echo "adding to menu : $menu_type_def : $hmc:$managedname:$ii - $i "; fi
             menu "$menu_type_def" "$hmc" "$managed1base_head" "$ii" "$name" "/$CGI_DIR/detail.sh?host=$hmc&type=$managedname&name=$ii&storage=$st_type&item=lpar&gui=1&none=none"
           fi
        done
        cd $pwd
      fi
    fi
  done
done

menu "$type_tmenu" "doc" "Documentation" "gui-help.html"
menu "$type_tmenu" "maincfg" "Main configuration cfg"  "/$CGI_DIR/log-cgi.sh?name=maincfg&gui=1"
menu "$type_tmenu" "scfg" "Storage configuration"  "/$CGI_DIR/log-cgi.sh?name=stcfg&gui=1"
menu "$type_tmenu" "acfg" "Alias configuration" "/$CGI_DIR/log-cgi.sh?name=aliascfg&gui=1"
menu "$type_tmenu" "elog" "Error log" "/$CGI_DIR/log-cgi.sh?name=errlog&gui=1"
menu "$type_tmenu" "errcgi" "Error log cgi-bin" "/$CGI_DIR/log-cgi.sh?name=errcgi&gui=1"

cp $MENU_OUT $MENU_OUT_FINAL

