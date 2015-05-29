#!/bin/ksh
#
# This is not used anymore!
#

A_YEAR=`date +"%Y"`
LANG=C


echo "Content-type: text/html"
echo ""
echo "<HTML> <HEAD> <TITLE>Historical reports</TITLE> </HEAD> "
echo "<BODY BGCOLOR=#D3D2D2 TEXT=#000000 LINK=#0000FF VLINK= #000080 ALINK=#FF0000 >"

# simple shell parse QUERY_STRING
for VAR in `echo $QUERY_STRING | tr "&" "\t"`
do
  NAME=$(echo "$VAR" | tr = " " | awk '{print $1}';)
  VALUE=$(echo "$VAR" | tr = " " | awk '{ print $2}' | tr + " "|sed -e 's/%20/ /g' -e 's/%23/#/g')
  export $NAME="$VALUE"
  #echo "$NAME=$VALUE" >> /tmp/e4
done


print_report () {
cat << END
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<HTML>
<HEAD>
  <TITLE>STOR2RRD</TITLE>
  <META HTTP-EQUIV="pragma" CONTENT="no-cache">
  <META HTTP-EQUIV="Expires" CONTENT="NOW">
  <META HTTP-EQUIV="last modified" CONTENT="NOW">
  <META HTTP-EQUIV="refresh" CONTENT="600">
<style>
<!--
a {text-decoration: none}
-->
</style>
</HEAD>
<BODY BGCOLOR="#D3D2D2" TEXT="#000000" LINK="#0000FF" VLINK="#0000FF" ALINK="#FF0000" >
<CENTER>
<TABLE BORDER=0 width=\"100%\"><tr><td align=\"center\"><h3>Historical reports</h3>
</td></tr></table>
  <FORM METHOD="GET" ACTION="/stor2rrd-cgi/stor2rrd-cgi.sh">
  <TABLE BORDER=0 CELLSPACING=5 SUMMARY="History reports">
    <TR> <TD>
          <SELECT NAME="start-hour">
 <OPTION VALUE="00-ddh" >00:00:00
 <OPTION VALUE="01-ddh" >01:00:00
 <OPTION VALUE="02-ddh" >02:00:00
 <OPTION VALUE="03-ddh" >03:00:00
 <OPTION VALUE="04-ddh" >04:00:00
 <OPTION VALUE="05-ddh" >05:00:00
 <OPTION VALUE="06-ddh" >06:00:00
 <OPTION VALUE="07-ddh" >07:00:00
 <OPTION VALUE="08-ddh" >08:00:00
 <OPTION VALUE="09-ddh" >09:00:00
 <OPTION VALUE="10-ddh" >10:00:00
 <OPTION VALUE="11-ddh" >11:00:00
 <OPTION VALUE="12-ddh" >12:00:00
 <OPTION VALUE="13-ddh" >13:00:00
 <OPTION VALUE="14-ddh" >14:00:00
 <OPTION VALUE="15-ddh" >15:00:00
 <OPTION VALUE="16-ddh" >16:00:00
 <OPTION VALUE="17-ddh" >17:00:00
 <OPTION VALUE="18-ddh" >18:00:00
 <OPTION VALUE="19-ddh" >19:00:00
 <OPTION VALUE="20-ddh" >20:00:00
 <OPTION VALUE="21-ddh" >21:00:00
 <OPTION VALUE="22-ddh" >22:00:00
 <OPTION VALUE="23-ddh" >23:00:00
          </SELECT>
          <SELECT NAME="start-day">
 <OPTION VALUE="01-ddy" >1
 <OPTION VALUE="02-ddy" >2
 <OPTION VALUE="03-ddy" >3
 <OPTION VALUE="04-ddy" >4
 <OPTION VALUE="05-ddy" >5
 <OPTION VALUE="06-ddy" >6
 <OPTION VALUE="07-ddy" >7
 <OPTION VALUE="08-ddy" >8
 <OPTION VALUE="09-ddy" >9
 <OPTION VALUE="10-ddy" >10
 <OPTION VALUE="11-ddy" >11
 <OPTION VALUE="12-ddy" >12
 <OPTION VALUE="13-ddy" >13
 <OPTION VALUE="14-ddy" >14
 <OPTION VALUE="15-ddy" >15
 <OPTION VALUE="16-ddy" >16
 <OPTION VALUE="17-ddy" >17
 <OPTION VALUE="18-ddy" >18
 <OPTION VALUE="19-ddy" >19
 <OPTION VALUE="20-ddy" >20
 <OPTION VALUE="21-ddy" >21
 <OPTION VALUE="22-ddy" >22
 <OPTION VALUE="23-ddy" >23
 <OPTION VALUE="24-ddy" >24
 <OPTION VALUE="25-ddy" >25
 <OPTION VALUE="26-ddy" >26
 <OPTION VALUE="27-ddy" >27
 <OPTION VALUE="28-ddy" >28
 <OPTION VALUE="29-ddy" >29
 <OPTION VALUE="30-ddy" >30
 <OPTION VALUE="31-ddy" >31
          </SELECT>
          <SELECT NAME="start-mon">
<OPTION VALUE="01-mmy" >Jan
<OPTION VALUE="02-mmy" >Feb
<OPTION VALUE="03-mmy" >Mar
<OPTION VALUE="04-mmy" >Apr
<OPTION VALUE="05-mmy" >May
<OPTION VALUE="06-mmy" >Jun
<OPTION VALUE="07-mmy" >Jul
<OPTION VALUE="08-mmy" >Aug
<OPTION VALUE="09-mmy" >Sep
<OPTION VALUE="10-mmy" >Oct
<OPTION VALUE="11-mmy" >Nov
<OPTION VALUE="12-mmy" >Dec
          </SELECT>
          <SELECT NAME="start-yr">
END


i=2006
while [ $i -lt $A_YEAR ]
do
echo "<OPTION VALUE=\"$i\" >$i"
(( i = i + 1))
done
echo "<OPTION VALUE=\"$i\" SELECTED >$i"

cat << END
          </SELECT>
           </td><td>to&nbsp;
          <SELECT NAME="end-hour">
 <OPTION VALUE="00-ddh" >00:00:00
 <OPTION VALUE="01-ddh" >01:00:00
 <OPTION VALUE="02-ddh" >02:00:00
 <OPTION VALUE="03-ddh" >03:00:00
 <OPTION VALUE="04-ddh" >04:00:00
 <OPTION VALUE="05-ddh" >05:00:00
 <OPTION VALUE="06-ddh" >06:00:00
 <OPTION VALUE="07-ddh" >07:00:00
 <OPTION VALUE="08-ddh" >08:00:00
 <OPTION VALUE="09-ddh" >09:00:00
 <OPTION VALUE="10-ddh" >10:00:00
 <OPTION VALUE="11-ddh" >11:00:00
 <OPTION VALUE="12-ddh" >12:00:00
 <OPTION VALUE="13-ddh" >13:00:00
 <OPTION VALUE="14-ddh" >14:00:00
 <OPTION VALUE="15-ddh" >15:00:00
 <OPTION VALUE="16-ddh" >16:00:00
 <OPTION VALUE="17-ddh" >17:00:00
 <OPTION VALUE="18-ddh" >18:00:00
 <OPTION VALUE="19-ddh" >19:00:00
 <OPTION VALUE="20-ddh" >20:00:00
 <OPTION VALUE="21-ddh" >21:00:00
 <OPTION VALUE="22-ddh" >22:00:00
 <OPTION VALUE="23-ddh" >23:00:00
 <OPTION VALUE="24-ddh" >24:00:00
          </SELECT>
          <SELECT NAME="end-day">
 <OPTION VALUE="01-ddd" >1
 <OPTION VALUE="02-ddd" >2
 <OPTION VALUE="03-ddd" >3
 <OPTION VALUE="04-ddd" >4
 <OPTION VALUE="05-ddd" >5
 <OPTION VALUE="06-ddd" >6
 <OPTION VALUE="07-ddd" >7
 <OPTION VALUE="08-ddd" >8
 <OPTION VALUE="09-ddd" >9
 <OPTION VALUE="10-ddd" >10
 <OPTION VALUE="11-ddd" >11
 <OPTION VALUE="12-ddd" >12
 <OPTION VALUE="13-ddd" >13
 <OPTION VALUE="14-ddd" >14
 <OPTION VALUE="15-ddd" >15
 <OPTION VALUE="16-ddd" >16
 <OPTION VALUE="17-ddd" >17
 <OPTION VALUE="18-ddd" >18
 <OPTION VALUE="19-ddd" >19
 <OPTION VALUE="20-ddd" >20
 <OPTION VALUE="21-ddd" >21
 <OPTION VALUE="22-ddd" >22
 <OPTION VALUE="23-ddd" >23
 <OPTION VALUE="24-ddd" >24
 <OPTION VALUE="25-ddd" >25
 <OPTION VALUE="26-ddd" >26
 <OPTION VALUE="27-ddd" >27
 <OPTION VALUE="28-ddd" >28
 <OPTION VALUE="29-ddd" >29
 <OPTION VALUE="30-ddd" >30
 <OPTION VALUE="31-ddd" >31
          </SELECT>
          <SELECT NAME="end-mon">
<OPTION VALUE="01-mmm" >Jan
<OPTION VALUE="02-mmm" >Feb
<OPTION VALUE="03-mmm" >Mar
<OPTION VALUE="04-mmm" >Apr
<OPTION VALUE="05-mmm" >May
<OPTION VALUE="06-mmm" >Jun
<OPTION VALUE="07-mmm" >Jul
<OPTION VALUE="08-mmm" >Aug
<OPTION VALUE="09-mmm" >Sep
<OPTION VALUE="10-mmm" >Oct
<OPTION VALUE="11-mmm" >Nov
<OPTION VALUE="12-mmm" >Dec
          </SELECT>
          <SELECT NAME="end-yr">
END


i=2006
while [ $i -lt $A_YEAR ]
do
echo "<OPTION VALUE=\"$i\" >$i"
(( i = i + 1))
done
echo "<OPTION VALUE=\"$i\"  SELECTED >$i"

cat << END
          </SELECT>
          </td></tr><tr><td colspan="2" align="center">
<B>Graph resolution</B> <input type="text" name="HEIGHT" value="150" size="1"> x <input type="text" name="WIDTH" value="900" size="1">
          </td></tr></table>

END
}

print_report_end () {
cat << END
        </SELECT>
          <BR><BR>
          <INPUT TYPE="SUBMIT" STYLE="font-weight: bold" NAME="Report" VALUE="Generate Report" ALT="Generate Report">
       </FORM>
<br><br></center>
<br><font size="-1">
You can select more rows via holding Ctrl/Shift.<br>
</font>

</BODY> </HTML>
END
}

print_items () {

    ALIAS_CFG="$INPUTDIR/etc/alias.cfg"

    echo "<TABLE BORDER=0><tr><th align=\"center\">Pool</th><th align=\"center\">Port</th>"
    if [ "$st_type" = "SWIZ" ]; then
      echo "<th align=\"center\">Mdisk</th><th align=\"center\">Volume</th></tr><tr>\n";
    else
      echo "<th align=\"center\">Rank</th><th align=\"center\">Volume</th></tr><tr>\n";
    fi

    # Pool
    echo "<td align=\"center\"><TABLE BORDER=0 width=\"100%\"><tr>"
    echo "  <td align=\"center\"><SELECT NAME=POOL MULTIPLE SIZE=23>"
    cd "$INPUTDIR/data/$storage/RANK"
    for item in `ls *.rrd| sed 's/^.*-P//g'|sort -n|uniq`
    do
      item_base=`basename $item .rrd`
      al=`egrep "^POOL:$storage:$item_base:" $ALIAS_CFG 2>/dev/null|awk -F: '{print $4}'`
      if [ ! "$al"x =  "x" ]; then
        echo " <OPTION VALUE=\"$item_base\" >$item_base - $al</OPTION>"
      else
        name=$item_base
        if [ -f "$INPUTDIR/data/$storage/pool.cfg" ]; then
          name=`egrep "^$item_base:" "$INPUTDIR/data/$storage/pool.cfg"|awk -F: '{print $2}'`
        fi
        echo " <OPTION VALUE=\"$item_base\" >$name</OPTION>"
      fi
    done
    echo "</td></tr></TABLE></td>"


    # Port
    echo "<td align=\"center\"><TABLE BORDER=0 width=\"100%\"><tr>"
    echo "  <td align=\"center\"><SELECT NAME=PORT MULTIPLE SIZE=23>"
    cd "$INPUTDIR/data/$storage/PORT"
    for item in *.rrd
    do
      item_base=`basename $item .rrd`
      al=`egrep "^PORT:$storage:$item_base:" $ALIAS_CFG 2>/dev/null|awk -F: '{print $4}'`
      if [ ! "$al"x =  "x" ]; then
        echo " <OPTION VALUE=\"$item_base\" >$item_base - $al</OPTION>"
      else
        echo " <OPTION VALUE=\"$item_base\" >$item_base</OPTION>"
      fi
    done
    echo "</td></tr></TABLE></td>"


    # Rank
    echo "<td align=\"center\"><TABLE BORDER=0 width=\"100%\"><tr>"
    echo "  <td align=\"center\"><SELECT NAME=RANK MULTIPLE SIZE=23>"
    cd "$INPUTDIR/data/$storage/RANK"
    for item in *.rrd
    do
      item_base=`basename $item .rrd`
      al=`egrep "^RANK:$storage:$item_base:" $ALIAS_CFG 2>/dev/null|awk -F: '{print $4}'`
      name=$item_base
      if [ -f "$INPUTDIR/data/$storage/mdisk.cfg" ]; then
         # SWIZ
         name_base=`echo $name|sed 's/-P.*$//'` # get rif of "-PXY" --> pool info
         name=`egrep "^$name_base:" "$INPUTDIR/data/$storage/mdisk.cfg"|awk -F: '{print $2}'`
      else 
         # DS8K
         name=`echo $item_base |sed -e 's/-P[0-9]//' -e 's/-P[0-9][0-9]//' -e 's/-P[0-9][0-9][0-9]//'`
      fi
      if [ ! "$al"x =  "x" ]; then
        echo " <OPTION VALUE=\"$item_base\" >$name - $al</OPTION>"
      else
        echo " <OPTION VALUE=\"$item_base\" >$name</OPTION>"
      fi
    done
    echo "</td></tr></TABLE></td>"


    # Volume
    echo "<td align=\"center\"><TABLE BORDER=0 ><tr>"
    echo "  <td align=\"center\"><SELECT NAME=VOLUME MULTIPLE SIZE=23>"
    for item in `cat $INPUTDIR/data/$storage/VOLUME/volumes.cfg 2>/dev/null|sed 's/ /====space====/g'`
    do
      item_base=`echo $item|sed -e 's/====space====/ /g' -e 's/ : .*$//'`
      al=`egrep "^VOLUME:$storage:$item_base:" $ALIAS_CFG 2>/dev/null|awk -F: '{print $4}'`
      if [ ! "$al"x =  "x" ]; then
        echo " <OPTION VALUE=\"$item_base\" >$item_base - $al</OPTION>"
      else
        echo " <OPTION VALUE=\"$item_base\" >$item_base</OPTION>"
      fi
    done
    echo "</td></tr></TABLE></td>"


    echo "</tr></TABLE>"

}

#
# find out yesterday date for historical reports
#

yesterday () {
YEAR=`date +"%Y"`
NMONTH=`date +"%m"`
DATE=`date +"%d"`

if [[ $DATE == 01 || $DATE == 1 ]]; then
# If its the first day of the month, set yesterday's date accordingly.

case $NMONTH in
01|02|04|06|08|09|11)
        DATE=31
        if [[ $NMONTH == "01" || $NMONTH == "1" ]]; then
                YEAR=`expr $YEAR - 1`
                NMONTH=12;LMONTH="December"
        else
         NMONTH=`expr $NMONTH - 1`
        fi;;


03)     if [[ `expr $YEAR % 4` -eq  0 ]]; then
                DATE=29
        else
                DATE=28
        fi
        NMONTH=`expr $NMONTH - 1`;;
*)
        DATE=30
        NMONTH=`expr $NMONTH - 1` ;;
esac

else
       DATE=`expr $DATE - 1`
fi

# If numeric month or date is <10, add a 0 in front
if [ ${#NMONTH} -eq 1 ]; then
  NMONTH="0$NMONTH"
fi
if [ ${#DATE} -eq 1 ]; then
 DATE="0$DATE"
fi

dayy=$DATE
monthy=$NMONTH
#year_y=$YEAR
#echo $DATE-$NMONTH-$YEAR #Output date-month-year
}




    hour=`date "+%H"`
    day=`date "+%d"`
    month=`date "+%m"`
    year=`date "+%Y"`

    # global definition for yesterday
    dayy=""
    monthy=""
    yesterday

    print_report|eval 'sed -e 's/=\\\"$hour-ddh\\\"/=\\\"$hour\\\"SELECTED/g' -e 's/=\\\"$day-ddd\\\"/=\\\"$day\\\"SELECTED/g' -e 's/=\\\"$month-mmm\\\"/=\\\"$month\\\"SELECTED/g' -e 's/=\\\"$dayy-ddy\\\"/=\\\"$dayy\\\"SELECTED/g' -e 's/=\\\"$monthy-mmy\\\"/=\\\"$monthy\\\"SELECTED/g' |sed -e 's/-mmm//g' -e 's/-ddd//g' -e 's/-mmy//g' -e 's/-ddy//g' -e 's/-ddh//g''
    echo "<INPUT type=\"hidden\" name=\"storage\" value=\"$storage\">"
    
    if [ -L "$INPUTDIR/data/$storage/MDISK" ]; then
      # SVC
      st_type="SWIZ"
    else
      st_type="DS8K"
    fi


    print_items



    print_report_end


