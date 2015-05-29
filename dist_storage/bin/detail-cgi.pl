
use strict;
use Date::Parse;

my $DEBUG = $ENV{DEBUG};
my $errlog = $ENV{ERRLOG};
my $xport = $ENV{EXPORT_TO_CSV};
my $webdir = $ENV{WEBDIR};
my $basedir = $ENV{INPUTDIR};
my $detail_yes = 1;
my $detail_no  = 0;
my $tmp_dir = "$basedir/tmp"; 
my $wrkdir = "$basedir/data";
my $time_u = time();


# CGI-BIN HTML header
print "Content-type: text/html\n\n";

open(OUT, ">> $errlog")  if $DEBUG == 2 ;

my @items_sorted = "sum_io sum_data io_rate data_rate sum_capacity read_io write_io read write cache_hit r_cache_hit w_cache_hit r_cache_usage w_cache_usage read_pct resp resp_t resp_t_r resp_t_w read_io_b write_io_b read_b write_b resp_t_b resp_t_r_b resp_t_w_b sys compress pprc_rio pprc_wio pprc_data_r pprc_data_w pprc_rt_r pprc_rt_w tier0 tier1 tier2 used io_rate-subsys data_rate-subsys read_io-subsys write_io-subsys read-subsys write-subsys data_cntl io_cntl ssd_r_cache_hit";

# get QUERY_STRING
use Env qw(QUERY_STRING);
print OUT "-- $QUERY_STRING\n" if $DEBUG == 2 ;

( my $host,my $type, my $name, my $st_type, my $item, my $gui, my $referer) = split(/&/,$QUERY_STRING);

# no URL decode here, as it goes immediately into URL again

$host =~ s/host=//;
my $host_url = $host;
$host =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$host =~ s/\+/ /g;
$host =~ s/%23/\#/g;
$type =~ s/type=//;
$name =~ s/name=//;
$name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
$name =~ s/\+/ /g;
$name =~ s/%23/\#/g;
$item =~ s/item=//;
$st_type =~ s/storage=//;

#print STDERR "$QUERY_STRING : $name\n";

if ( $gui =~ m/gui=/ ) {
  $gui =~ s/gui=//;
}
else {
  $gui=0;
}
# http_base must be passed through cgi-bin script to get location of jquery scripts and others
# it is taken from HTTP_REFERER first time and then passed in the HTML GET
my $html_base = "";
$referer =~ s/referer=//;    #for paging aggregated : PH: not only for paging!!

if ( $referer ne "" && $referer !~ m/none=/ ) {
  # when is referer set then it is already html_base --> not call html_base($refer) again
  $referer =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/seg;
  $referer =~ s/\+/ /g;
  $html_base = $referer ;
}
else {
  $referer = $ENV{HTTP_REFERER};
  $html_base = html_base($referer); # it must be here behind $base setting
}

if ( $name =~ m/^top$/ ) {
  # volumes text tables
  # must be before $item =~ m/^sum$/
  volumes_top_all($host,$type,$item,$st_type,$name);
  exit (0);
} 

if ( $item =~ m/^sum$/ ) {
  # aggregated graphs
  make_agg($host,$type,$name,$item,$st_type);
  exit (0);
} 


# individual "item" graohs
create_tab($host,$type,$name,$st_type,$item);

sub create_tab 
{
  my ($host,$type,$name,$st_type,$item)= @_;

  my $item="data_rate";
  my @graph = "";
  my $graph_indx = 0;

  foreach $item (<@items_sorted>) {
    #print STDERR "01 $item $host $type : $tmp_dir/$host/$type-$item-d.cmd : $QUERY_STRING\n";

    if ( $item =~ m/-subsys/ ) {
      next; # skip Storwize  PORT subsys graphs per port, they are only in agg graphs
    }

    if ( ! -f "$tmp_dir/$host/$type-$item-d.cmd" ) {
       next; # non existing item
    }

    if ( $name !~ m/^sum/ && $item =~ m/^sum/ ) {
      next; # avoid sum graphs for normail item details
    }

    if ( $item =~ m/^sum_capacity$/ && $st_type =~ m/DS8K/ ) {
      next;
    }
  
    if ( $item =~ m/_cntl$/ ) {
      next; # controller info is only for aggregated, not for individual pools or volumes
    }

    #print STDERR "02 $item $host $type\n";

    if ( $type =~ m/^POOL$/ ) {
      if ( $item =~ m/^read$/ && $st_type !~ m/XIV/ && $st_type !~ m/DS8K/ ) {
        $item = "data_rate";
      }
      if ( $item =~ m/^read_io$/ && $st_type !~ m/XIV/ && $st_type !~ m/DS8K/ ) {
        $item = "io_rate";
      }
      if ( $st_type =~ m/SWIZ/ ) {
        if ( $item !~ m/^read_io_b$/ && $item !~ m/^write_io_b$/ && $item !~ m/^read_b$/ && $item !~ m/^write_b$/ && $item !~ m/^resp_t_r_b$/ && $item !~ m/^resp_t_w_b$/ &&
             $item !~ m/tier/ && $item !~ m/^sum_capacity$/ && $item !~ m/^io_rate$/ && $item !~ m/^data_rate$/ && $item !~ m/resp/ ) {
          next;
        }
      }
      if ( $st_type =~ m/DS8K/ ) {
        if ( $item !~ m/tier/ && $item !~ m/^read_io$/ && $item !~ m/^write_io$/ && $item !~ m/^read_io_b$/ && $item !~ m/^write_io_b$/ &&
             $item !~ m/^resp_t_r$/ && $item !~ m/^resp_t_w$/ &&
             $item !~ m/^read$/ && $item !~ m/^write$/ && $item !~ m/^read_b$/ && $item !~ m/^write_b$/ && $item !~ m/^resp_t_r_b$/ && $item !~ m/^resp_t_w_b$/ ) {
          next;
        }
      }
      if ( $st_type =~ m/DS5K/ && $item =~ m/cache/ ) {
        next;
      }
    }
    if ( $st_type =~ m/DS8K/ && $type =~ m/^PORT$/ && $item =~ /^pprc/ ) {
      if ( ! -f "$basedir/data/$host/$type/$name.rrp" ) {
        # display PPRC tabs only where are some PPRC data (data file *.rrp)
        next;
      }
    }

    if ( $type =~ m/^HOST$/ ) {
      if ( ! -f "$basedir/data/$host/$type/hosts.cfg" || find_vols ($host,$type,$name) == 0 ) {
        # when a host does not have any attached volume then print message and exit
        non_existing_data($host,$name);
        exit (0);
      }
      # add "?" with How it works link
      print "<div id=\'hiw\'><a href=\'http://www.stor2rrd.com/host_docu.htm\' target=\'_blank\'><img src=\'css/images/help-browser.gif\' alt=\'How it works?\' title=\'How it works?\'></a></div>\n";
    }

    #print STDERR "02 $item $host $type : $tmp_dir/$host/$type-$item-d.cmd : $QUERY_STRING\n";
    $graph[$graph_indx] = $item;
    $graph_indx++;
    if ( $st_type =~ m/SWIZ/ && $item =~ /^sys$/ ) {
      # add compress 
      $graph[$graph_indx] = "compress";
      $graph_indx++;
    }
  }

  # print out tabs
  my $tab_number = 0;
  print "<div  id=\"tabs\"> <ul>\n";
  foreach $item (<@graph>) {
    # data source back/fron end
    my $data_type = "tabfrontend";
    if ( $item =~ m/_b$/ ) {
      $data_type = "tabbackend";
    }
  
    my $tab_name = text_tab($item,"item");
    print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">$tab_name</a></li>\n";
    $tab_number++;
  }
  print "   </ul> \n";

  $tab_number = 0;
  foreach $item (<@graph>) {
    my $item_name = $item;

    print "<div id=\"tabs-$tab_number\"><br><br><center>\n";
    if ( $gui == 0 ) {
      print "<center><h3>$item_name</h3></center>";
    }
  
    print "<table align=\"center\" summary=\"Graphs\">\n";
  
    print "<tr>\n";
    print_item ($host,$type,$name,$item,"d",$detail_yes);
    print_item ($host,$type,$name,$item,"w",$detail_yes);
    print "</tr><tr>\n";
    print_item ($host,$type,$name,$item,"m",$detail_yes);
    print_item ($host,$type,$name,$item,"y",$detail_yes);
    print "</tr>\n";
    print "</table></center>\n";
    print "</div>\n";
    $tab_number++;
  }

  print "</div><br>\n";
  if ( $gui == 0 ) {
    print "</BODY></HTML>";
  }
} # create_tab

  
sub html_base
{
  my $refer = shift;

    # Print link to full lpar cfg (must find out at first html_base
    # find out HTML_BASE
    # renove from the path last 3 things
    # http://nim.praha.cz.ibm.com/lpar2rrd/hmc1/PWR6B-9117-MMA-SN103B5C0%20ttt/pool/top.html
    # --> http://nim.praha.cz.ibm.com/lpar2rrd
    my $html_base = "";
      my @full_path = split(/\//, $refer);
      my $k = 0;
      foreach my $path (@full_path){
        $k++
      }
      $k--;
      if ( $refer !~ m/topten-glo/ && $refer !~ m/cpu_max_check/ ) { # when top10 global then just once
        $k--; $k--;
      }
      my $j = 0;
      foreach my $path (@full_path){
        if ($j < $k) {
          if ( $j == 0 ) {
            $html_base .= $path;
          }
          else {
            $html_base .= "/".$path;
          }
          $j++;
        }
      }

    return $html_base;
}

sub make_agg
{
  my $host = shift;
  my $type = shift;
  my $name = shift;
  my $item = shift;
  my $st_type = shift;
  my $cache_once = 0;

  # list of all items with its priority
  my @items_high = "io data resp cap cache cpu pprc";


  # print out tabs
  my $tab_number = 0;
  print "<div  id=\"tabs\"> <ul>\n";

  # go though all @items_high and check if at least one is available
  my $data_string = "sum_data data data_rate read write read_b write_b";


  # create tab header
  foreach my $item_high (<@items_high>) {
    #print STDERR "00 - $item_high - $name -\n";
    if ( $name !~ m/$item_high/ ) {
      next;
    }
    foreach my $name_act (<@items_sorted>) {
      #print STDERR "01 $item_high,$name_act\n";
      if ( ! -f "$tmp_dir/$host/$type-$name_act-d.cmd" ) {
        next; # non existing metric
      }
      
      if ($item_high !~ m/^cpu$/ && $item_high !~ m/^cap$/ && $name_act !~ m/data/ && $name_act !~ m/^read$/ && $name_act !~ m/^write$/ && $name_act !~ m/$item_high/ && $name_act !~ m/^read_b$/ && $name_act !~ m/^write_b$/ && $name_act !~ m/-subsys$/ ) {
        next;
      }

      #print STDERR "03 $item_high,$name_act: $item_high - $data_string\n";
      if ($name_act =~ m/data/ || $name_act =~ m/^read$/ || $name_act =~ m/^write$/ || $name_act =~ m/^read_b$/ || $name_act =~ m/^write_b$/) {
        if ( $data_string !~ m/$item_high / && $name_act !~ m/pprc/ && $name_act !~ m/-subsys$/ ) {
          next;
        }
      }

      #print STDERR "04 $item_high,$name_act: $item_high - $data_string\n";
      # capacity POOL
      if ($item_high =~ m/^cap$/ ) {
        if ( $name_act !~ m/^tier/ && $name_act !~ m/^used$/ && $name_act !~ m/^sum_capacity$/ ) {
          next;
        }
      }
      #print STDERR "05 $item_high,$name_act: $item_high - $data_string\n";

      # port and data_rate && io_rate vrs PPRC ....
      if ( $item_high =~ m/data/ || $item_high =~ m/io/ )  {
        if ( $type =~ /PORT/ && $name_act =~ m/pprc/ ) {
          next;
        }
      }
      #print STDERR "06 $item_high,$name_act\n";

      

      # found it, create the page and tabs  

      # data source back/fron end
      my $data_type = "tabfrontend";
      if ( $type =~ /^RANK$/ ) {
        $data_type = "tabbackend";
      }
      if ( $type =~ /^POOL$/ && $st_type !~ m/^DS8K$/ && $st_type !~ m/^SWIZ$/ ) {
        $data_type = "tabbackend";
      }
      if ( $st_type =~ m/^DS5K$/ ) {
        $data_type = "tabfrontend";
      }
      if ( $name_act =~ m/_b$/ ) {
        $data_type = "tabbackend";
      }
      if ( $item_high =~ m/cache/ && $cache_once == 0 ) {
        # cache for storwirwize, table, not graphs
        if ( -f "$webdir/$host/cache-r_cache_hit.html" ) {
          print "  <li class=\"$data_type\"><a href=\"$host/cache-r_cache_hit.html\">read hit avrg</a></li>\n";
        }
        if ( -f "$webdir/$host/cache-w_cache_hit.html" ) {
          print "  <li class=\"$data_type\"><a href=\"$host/cache-w_cache_hit.html\">write hit avrg</a></li>\n";
        }
        if ( -f "$webdir/$host/cache-cache_hit.html" ) {
          print "  <li class=\"$data_type\"><a href=\"$host/cache-cache_hit.html\">cache hit avrg</a></li>\n";
        }
        if ( -f "$webdir/$host/cache-read_pct.html" ) {
          print "  <li class=\"$data_type\"><a href=\"$host/cache-read_pct.html\">read percent avrg</a></li>\n";
        }
        if ( -f "$webdir/$host/cache-ssd_r_cache_hit.html" ) {
          print "  <li class=\"$data_type\"><a href=\"$host/cache-ssd_r_cache_hit.html\">SSD read cache hit avrg</a></li>\n";
        }
        $cache_once++;
      }

      my $tab_name = text_tab($name_act,"aggregated");
      print "  <li class=\"$data_type\"><a href=\"#tabs-$tab_number\">$tab_name</a></li>\n";
      $tab_number++;
      #print STDERR "01 $item_high,$host,$type,$name_act,$st_type,$item\n";
    }
  }
  print "</ul>\n";

  my $tab_number = 0;
  $cache_once = 0;
  # create body of the tabs
  foreach my $item_high (<@items_high>) {
    if ( $name !~ m/$item_high/ ) {
      next;
    }
    foreach my $name_act (<@items_sorted>) {
      if ( ! -f "$tmp_dir/$host/$type-$name_act-d.cmd" ) {
        next; # non existing metric
      }
      if ($item_high !~ m/^cpu$/ && $item_high !~ m/^cap$/ && $name_act !~ m/data/ && $name_act !~ m/^read$/ && $name_act !~ m/^write$/ && $name_act !~ m/$item_high/ && $name_act !~ m/^read_b$/ && $name_act !~ m/^write_b$/ && $name_act !~ m/-subsys$/ ) {
        next;
      }
      if ($name_act =~ m/data/ || $name_act =~ m/^read$/ || $name_act =~ m/^write$/ || $name_act =~ m/^read_b$/ || $name_act =~ m/^write_b$/) {
        if ( $data_string !~ m/$item_high / && $name_act !~ m/pprc/ && $name_act !~ m/-subsys$/ ) {
          next;
        }
      }

      # capacity POOL
      if ($item_high =~ m/^cap$/ ) {
        if ( $name_act !~ m/^tier/ && $name_act !~ m/^used$/ && $name_act !~ m/^sum_capacity$/ ) {
          next;
        }
      }

      # port and data_rate && io_rate vrs PPRC ....
      if ( $item_high =~ m/data/ || $item_high =~ m/io/ )  {
        if ( $type =~ /PORT/ && $name_act =~ m/pprc/ ) {
          next;
        }
      }
      # found it, create the page and tabs  

      # data source back/fron end
      my $data_type = "tabfrontend";
      if ( $type =~ /^RANK$/ || $type =~ /^POOL$/ || $name_act =~ m/_b$/ ) {
        $data_type = "tabbackend";
      }
      if ( $st_type =~ m/^DS5K$/ ) {
        $data_type = "tabfrontend";
      }

      print "<div id=\"tabs-$tab_number\"><br><br><center>\n";
      $tab_number++;
      create_tab_agg($item_high,$host,$type,$name_act,$st_type,$item);
      print "</div>\n";
    }
  }
  print "</div>\n";

}


sub create_tab_agg
{
  my ($item_high,$host,$type,$name,$st_type,$item) = @_;

  print "<table align=\"center\" summary=\"Graphs\">\n";

  print "<tr>\n";
  print_item ($host,$type,$name,$item,"d",$detail_yes);
  print_item ($host,$type,$name,$item,"w",$detail_yes);
  print "</tr><tr>\n";
  print_item ($host,$type,$name,$item,"m",$detail_yes);
  print_item ($host,$type,$name,$item,"y",$detail_yes);
  print "</tr>\n";
  print "</table>\n";

  return 1;
}

sub print_item
{
  my ($host,$type,$name,$item,$time,$detail) = @_;
  my $refresh = "";
  my $legend_class = "nolegend";

  if ($item !~ /^sum/) {
	$legend_class = ""; 
  }
  if ($name =~ /^sum/) {
	$legend_class = "";
  }
  if (( $name =~ m/^sum_data$/ ) ||
      ( $name =~ m/^sum_io$/ )   ||
      ( $name =~ m/^sum_capacity$/ ) ||
      ( $name =~ m/^tier0$/ )    ||
      ( $name =~ m/^tier1$/ )    ||
      ( $name =~ m/^tier2$/ )    ||
      ( $name =~ m/^io_rate-subsys$/ )    ||
      ( $name =~ m/^data_rate-subsys$/ )  ||
      ( $name =~ m/^read_io-subsys$/ )    ||
      ( $name =~ m/^write_io-subsys$/ )   ||
      ( $name =~ m/^read-subsys$/ )    ||
      ( $name =~ m/^write-subsys$/ )   ||
      ( $name =~ m/^used$/ )   ||
      ( $name =~ m/^sys$/ )
     ) {
      $legend_class = "";
  }
  if ($type =~ m/HOST/) {
	$legend_class = "nolegend";
  }

  # It must be here otherwise does notwork for example "#" in the $name
  $name =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  $host =~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;
  # print STDERR "009 print_item enter:$host,$type,$name,$item,$time,$detail,$legend_class,\n";

  if ( $detail > 0 ) {
    print "<td valign=\"top\" class=\"relpos\">
      <div>
        <div class=\"favs favoff\"></div>
        <div class=\"popdetail\"></div>$refresh
        <a class=\"detail\" href=\"/stor2rrd-cgi/detail-graph.sh?host=$host&type=$type&name=$name&item=$item&time=$time&detail=1&none=$time_u\">
        <div title=\"Click to show detail\">
        <img class=\"lazy $legend_class\" border=\"0\" data-src=\"/stor2rrd-cgi/detail-graph.sh?host=$host&type=$type&name=$name&item=$item&time=$time&detail=0&none=$time_u\" src=\"$html_base/jquery/images/loading.gif\">
        <div class=\"zoom\" title=\"Click and drag to select range\"></div>
        </div>
        </a>
        <div class=\"legend\"></div>
        <div class=\"updated\"></div>
      </div>
      </td>\n";
  }
  else {
    print "<td align=\"center\" valign=\"top\" colspan=\"2\"><div><img class=\"lazy\" border=\"0\" data-src=\"/stor2rrd-cgi/detail-graph.sh?host=$host&type=$type&name=$name&item=$item&time=$time&detail=0&none=$time_u\" src=\"$html_base/jquery/images/loading.gif\"></div></td>\n";
  }
  return 1;
}

sub basename {
  my $full = shift;
  my $out = "";

  # basename without direct function
  my @base = split(/\//,$full);
  foreach my $m (@base) {
    $out = $m;
  }

  return $out;
}

sub text_tab 
{
  my $text_inp = shift;
  my $type = shift;
  my $text_out = $text_inp;

  if ( $type =~ m/^aggregated$/ ) {
    if ( $text_inp =~ m/^sum_io$/ ) { $text_out = "total"; };
    if ( $text_inp =~ m/^sum_data$/ ) { $text_out = "total"; };
    if ( $text_inp =~ m/^io_rate$/ ) { $text_out = "total"; };
    if ( $text_inp =~ m/^data_rate$/ ) { $text_out = "total"; };
    if ( $text_inp =~ m/^sum_capacity$/ ) { $text_out = "capacity"; };
    if ( $text_inp =~ m/^read_io$/ ) { $text_out = "read"; };
    if ( $text_inp =~ m/^write_io$/ ) { $text_out = "write"; };
    if ( $text_inp =~ m/^read$/ ) { $text_out = "read"; };
    if ( $text_inp =~ m/^write$/ ) { $text_out = "write"; };
    if ( $text_inp =~ m/^r_cache_hit$/ ) { $text_out = "read hit"; };
    if ( $text_inp =~ m/^w_cache_hit$/ ) { $text_out = "write hit"; };
    if ( $text_inp =~ m/^r_cache_usage$/ ) { $text_out = "read usage"; };
    if ( $text_inp =~ m/^w_cache_usage$/ ) { $text_out = "write usage"; };
    if ( $text_inp =~ m/^resp_t$/ ) { $text_out = "total"; };
    if ( $text_inp =~ m/^resp_t_r$/ ) { $text_out = "read"; };
    if ( $text_inp =~ m/^resp_t_w$/ ) { $text_out = "write"; };
    if ( $text_inp =~ m/^read_io_b$/ ) { $text_out = "read back"; };
    if ( $text_inp =~ m/^write_io_b$/ ) { $text_out = "write back"; };
    if ( $text_inp =~ m/^read_b$/ ) { $text_out = "read back"; };
    if ( $text_inp =~ m/^write_b$/ ) { $text_out = "write back"; };
    if ( $text_inp =~ m/^resp_t_b$/ ) { $text_out = "total back"; };
    if ( $text_inp =~ m/^resp_t_r_b$/ ) { $text_out = "read back"; };
    if ( $text_inp =~ m/^resp_t_w_b$/ ) { $text_out = "write back"; };
    if ( $text_inp =~ m/^sys$/ ) { $text_out = "CPU"; };
    if ( $text_inp =~ m/^compress$/ ) { $text_out = "compress"; };
    if ( $text_inp =~ m/^pprc_rio$/ ) { $text_out = "IO read"; };
    if ( $text_inp =~ m/^pprc_wio$/ ) { $text_out = "IO write"; };
    if ( $text_inp =~ m/^pprc_data_r$/ ) { $text_out = "read"; };
    if ( $text_inp =~ m/^pprc_data_w$/ ) { $text_out = "write"; };
    if ( $text_inp =~ m/^pprc_rt_r$/ ) { $text_out = "resp read"; };
    if ( $text_inp =~ m/^pprc_rt_w$/ ) { $text_out = "resp write"; };
    if ( $text_inp =~ m/^tier0$/ ) { $text_out = "tier 0"; };
    if ( $text_inp =~ m/^tier1$/ ) { $text_out = "tier 1"; };
    if ( $text_inp =~ m/^tier2$/ ) { $text_out = "tier 2"; };
    if ( $text_inp =~ m/^used$/ ) { $text_out = "used"; };
    if ( $text_inp =~ m/^cache_hit$/ ) { $text_out = "cache hit"; };
    if ( $text_inp =~ m/^data_cntl$/ ) { $text_out = "controller"; };
    if ( $text_inp =~ m/^io_cntl$/ ) { $text_out = "controller"; };
    if ( $text_inp =~ m/^ssd_r_cache_hit$/ ) { $text_out = "SSD read cache hit"; };
  }
  else {
    if ( $text_inp =~ m/^sum_io$/ ) { $text_out = "IO"; };
    if ( $text_inp =~ m/^sum_data$/ ) { $text_out = "data"; };
    if ( $text_inp =~ m/^io_rate$/ ) { $text_out = "IO"; };
    if ( $text_inp =~ m/^data_rate$/ ) { $text_out = "data"; };
    if ( $text_inp =~ m/^sum_capacity$/ ) { $text_out = "capacity"; };
    if ( $text_inp =~ m/^read_io$/ ) { $text_out = "IO read"; };
    if ( $text_inp =~ m/^write_io$/ ) { $text_out = "IO write"; };
    if ( $text_inp =~ m/^read$/ ) { $text_out = "read"; };
    if ( $text_inp =~ m/^write$/ ) { $text_out = "write"; };
    if ( $text_inp =~ m/^r_cache_hit$/ ) { $text_out = "read cache hit"; };
    if ( $text_inp =~ m/^w_cache_hit$/ ) { $text_out = "write cache hit"; };
    if ( $text_inp =~ m/^r_cache_usage$/ ) { $text_out = "read usage"; };
    if ( $text_inp =~ m/^w_cache_usage$/ ) { $text_out = "write usage"; };
    if ( $text_inp =~ m/^resp_t$/ ) { $text_out = "resp time"; };
    if ( $text_inp =~ m/^resp_t_r$/ ) { $text_out = "resp read"; };
    if ( $text_inp =~ m/^resp_t_w$/ ) { $text_out = "resp write"; };
    if ( $text_inp =~ m/^read_io_b$/ ) { $text_out = "IO read back"; };
    if ( $text_inp =~ m/^write_io_b$/ ) { $text_out = "IO write back"; };
    if ( $text_inp =~ m/^read_b$/ ) { $text_out = "read back"; };
    if ( $text_inp =~ m/^write_b$/ ) { $text_out = "write back"; };
    if ( $text_inp =~ m/^resp_t_b$/ ) { $text_out = "resp time back"; };
    if ( $text_inp =~ m/^resp_t_r_b$/ ) { $text_out = "resp read back"; };
    if ( $text_inp =~ m/^resp_t_w_b$/ ) { $text_out = "resp write back"; };
    if ( $text_inp =~ m/^sys$/ ) { $text_out = "CPU"; };
    if ( $text_inp =~ m/^compress$/ ) { $text_out = "compress"; };
    if ( $text_inp =~ m/^pprc_rio$/ ) { $text_out = "PPRC IO read"; };
    if ( $text_inp =~ m/^pprc_wio$/ ) { $text_out = "PPRC IO write"; };
    if ( $text_inp =~ m/^pprc_data_r$/ ) { $text_out = "PPRC read"; };
    if ( $text_inp =~ m/^pprc_data_w$/ ) { $text_out = "PPRC write"; };
    if ( $text_inp =~ m/^pprc_rt_r$/ ) { $text_out = "PPRC resp read"; };
    if ( $text_inp =~ m/^pprc_rt_w$/ ) { $text_out = "PPRC resp write"; };
    if ( $text_inp =~ m/^tier0$/ ) { $text_out = "tier 0"; };
    if ( $text_inp =~ m/^tier1$/ ) { $text_out = "tier 1"; };
    if ( $text_inp =~ m/^tier2$/ ) { $text_out = "tier 2"; };
    if ( $text_inp =~ m/^used$/ ) { $text_out = "used"; };
    if ( $text_inp =~ m/^read_pct$/ ) { $text_out = "read percent"; };
    if ( $text_inp =~ m/^cache_hit$/ ) { $text_out = "cache hit"; };
    if ( $text_inp =~ m/^ssd_r_cache_hit$/ ) { $text_out = "SSD read cache hit"; };
  }
  
    return $text_out;
}


sub non_existing_data
{
  my $host = shift;
  my $name = shift;

  print "There is no any volume attached to that host: $name\n";
  
  return 0;
}

sub find_vols
{
  my $host = shift;
  my $type = shift;
  my $lpar = shift;

  if ( ! -f "$wrkdir/$host/$type/hosts.cfg" ) {
    return 0;
  }
  open(FHH, "< $wrkdir/$host/$type/hosts.cfg") || error ("Can't open $wrkdir/$host/$type/hosts.cfg : $! ".__FILE__.":".__LINE__) && return "";
  my @hosts = <FHH>;
  close(FHR);

  foreach my $line (@hosts) {
    chomp ($line);
    (my $host_name, my $volumes ) = split (/ : /,$line);
    if ( ! defined ($volumes) ) {
      next;
    }
    $volumes =~ s/ //g;

    # must be used this no regex construction otherwise m// does not work with names with ()
    if ( $host_name eq $lpar && ! $volumes eq '' ) {
      return 1;
    }
  }
  return 0;
}

sub volumes_top_all
{
  my $host = shift;
  my $type = shift;
  my $item = shift;
  my $st_type = shift;
  my $name = shift;
  my $CGI_DIR = "stor2rrd-cgi";
  my $time_unix = time();
  my $data_type = "tabfrontend";
  my $class = "class=\"$data_type\"";
  my $class_url = "class=\"lazy\" src=\"$html_base/jquery/images/loading.gif\"";
  $class_url = "";
 
  # print tab page only
  print "<div  id=\"tabs\"> <ul>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=avrg&time=d&detail=0&none=$time_unix\">daily</a></li>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=avrg&time=w&detail=0&none=$time_unix\">weekly</a></li>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=avrg&time=m&detail=0&none=$time_unix\">monthly</a></li>\n";
  #print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=avrg&time=y&detail=0&none=$time_unix\">yearly</a></li>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=max&time=d&detail=0&none=$time_unix\">daily max</a></li>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=max&time=w&detail=0&none=$time_unix\">weekly max</a></li>\n";
  print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=max&time=m&detail=0&none=$time_unix\">monthly max</a></li>\n";
  #print "  <li $class><a $class_url href=\"/$CGI_DIR/detail-graph.sh?host=$host&type=$type&name=$name&item=max&time=y&detail=0&none=$time_unix\">yearly max</a></li>\n";
  print "</ul> \n";
  print "</div>\n";
    
  return 1;
}

sub error
{
  my $text = shift;
  my $act_time = localtime();

  if ( $text =~ m/no new input files, exiting data load/ ) {
    print "ERROR          : $text \n";
    print STDERR "$act_time: $text \n";
  }
  else {
    print "ERROR          : $text : $!\n";
    print STDERR "$act_time: $text : $!\n";
  }

  return 1;
}

