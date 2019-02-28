#! /usr/bin/perl -w

use strict;
use Carp;
use warnings;
use DBI;
use JSON;
use CGI;
use Redis;

my $redis = Redis->new;

my $q = CGI->new();

my $ltconditions;
if ($q->param('start') && $q->param('end')){
  if ($q->param('start') eq $q->param('end')){
    $ltconditions = "lt.year=" . $q->param('end');
  }
  else{
    $ltconditions = "lt.year>=" . $q->param('start') . " and lt.year<=" . $q->param('end');
  }
}
else{
  $ltconditions = "lt.year=2017";
}

if (defined($q->param('rentstart')) && defined($q->param('rentend'))){
  if (int($q->param('rentstart')) != 0){
    $ltconditions .= " and ongoing_rent >= " . $q->param('rentstart');
  }
  if (int($q->param('rentend')) != 2000){
    $ltconditions .= " and ongoing_rent < " . $q->param('rentend');
  }
}

if ($q->param('zip')){
  $ltconditions .= " and zip='" . $q->param('zip') . "'";
}
if ($q->param('census')){
  $ltconditions .= " and census like '%" . $q->param('census') . "%'";
}
foreach my $key ("a", "b", "c", "publichousing", "defendant_represented", "plaintiff_represented"){
  if (defined($q->param($key))){
    if ($q->param($key) eq "True"){
      $ltconditions .= " and $key";
    }
    elsif ($q->param($key) eq "False"){
      $ltconditions .= " and not $key";
    }
  }
}

print STDERR "Conditions are $ltconditions\n";

my $redis_key = 'sankey:' . $ltconditions;

my $cache_result = $redis->get($redis_key);
if ($cache_result){
  print $q->header('text/json');
  print $cache_result;
  exit;
}

my $dref = DBI->connect('dbi:Pg:dbname=eviction;host=localhost', 'jpyle', 'foobar', {AutoCommit => 1}) or croak DBI->errstr;

my %value;
my %query_list = (
		  "case filed" => "select count(distinct a.id) from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) where a.eventtype='CF'",
		  "default judgment" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='DJ' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "withdrawn" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='WD' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFD', 'JFP', 'DJ')) as aa;",
		  "withdrawn and then relisted" => "select count(distinct a.id) from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, min(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFD', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (b.id=c.id and c.eventdate < b.eventdate) where a.eventtype='CF' and c.eventtype='WD';",
		  "petition to open" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (b.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and b.eventtype='DJ' and c.eventtype='PO' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "petition to open granted" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (b.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate > c.eventdate) where a.eventtype='CF' and b.eventtype='DJ' and c.eventtype='PO' and d.eventtype='POG' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "petition to open denied" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (b.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate > c.eventdate) where a.eventtype='CF' and b.eventtype='DJ' and c.eventtype='PO' and d.eventtype='POD' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "hearing date" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFD', 'JFP') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "hearing, no petition to open" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFD', 'JFP') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='DJ' or eventtype='WD') as aa;",
		  "any judgment" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ', 'POD') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "JBA" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='JBA' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "judgment for defendant" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='JFD' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "judgment for plaintiff" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='JFP' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "satisfied DJ" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join ltevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and b.eventtype='DJ' and c.eventtype like 'SAT%' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "judgment satisfied" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'SATB' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "judgment satisfied no writ" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'SATB' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'WP', 'AW', 'AWS')) as aa;",
		  "judgment satisfied after writ" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate >= c.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' and d.eventtype like 'SATB' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'AW', 'AWS')) as aa;",
		  "judgment satisfied after alias writ" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate >= c.eventdate) inner join ltevents as e on (a.id=e.id and e.eventdate >= d.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' and d.eventtype='AW' and e.eventtype like 'SATB' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'AWS')) as aa;",
		  "judgment satisfied after alias writ served" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate >= c.eventdate) inner join ltevents as e on (a.id=e.id and e.eventdate >= d.eventdate) inner join ltevents as f on (a.id=f.id and f.eventdate >= e.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' and d.eventtype='AW' and e.eventtype='AWS' and f.eventtype like 'SATB' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "writ of possession" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "alias writ" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate > c.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' and d.eventtype='AW' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "alias writ served" => "select count(distinct id) from (select a.id from ltevents as a inner join ltdatahist as lt on (a.id=lt.id and $ltconditions) inner join (select ltevents.id, max(eventdate) as eventdate from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype in ('JBA', 'JFP', 'DJ') group by ltevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join ltevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join ltevents as d on (a.id=d.id and d.eventdate > c.eventdate) inner join ltevents as e on (a.id=e.id and e.eventdate > d.eventdate) where a.eventtype='CF' and c.eventtype like 'WP' and d.eventtype='AW' and e.eventtype='AWS' except select ltevents.id from ltevents inner join ltdatahist as lt on (ltevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		 );

my %r = (nodes => [], links => []);
my $start_time = time();
foreach my $key (sort keys %query_list){
  my $query_string = $query_list{$key};
  if ($key ne "hearing, no petition to open" && $key ne "satisfied DJ" && $key ne "withdrawn and then relisted" && $key ne "judgment satisfied no writ" && $key ne "judgment satisfied after writ" && $key ne "judgment satisfied after alias writ" && $key ne "judgment satisfied after alias writ served"){
    if ($key eq "withdrawn"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posX" => 200, "posY" => 0});
    }
    elsif ($key eq "default judgment"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posX" => 300, "posYbot" => 700});
    }
    elsif ($key eq "hearing date"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 70});
    }
    elsif ($key eq "petition to open"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment"});
    }
    elsif ($key eq "petition to open granted"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment", "posYoff" => -40});
    }
    elsif ($key eq "petition to open denied"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment", "posYoff" => -20});
    }
    elsif ($key eq "JBA"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 170});
    }
    elsif ($key eq "judgment for defendant"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 10, "posXrel" => "judgment for plaintiff"});
    }
    elsif ($key eq "judgment for plaintiff"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 50});
    }
    elsif ($key eq "judgment satisfied"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 10});
    }
    else{
      push(@{$r{nodes}}, {"id" => $key, "name" => $key});
    }
  }
  print STDERR "Running $key at " . (time() - $start_time) . "\n";
  my $query = $dref->prepare($query_string) or croak $dref->errstr;
  $query->execute() or croak $query->errstr;
  while (my @row = $query->fetchrow_array){
    $value{$key} = $row[0];
  }
}

push(@{$r{links}}, {"source" => "case filed", "target" => "withdrawn", "value" => $value{"withdrawn"}});
push(@{$r{links}}, {"source" => "case filed", "target" => "hearing date", "value" => $value{"hearing date"} - $value{"petition to open granted"}});
push(@{$r{links}}, {"source" => "case filed", "target" => "default judgment", "value" => $value{"default judgment"}});
push(@{$r{links}}, {"source" => "default judgment", "target" => "petition to open", "value" => $value{"petition to open"}});
push(@{$r{links}}, {"source" => "petition to open", "target" => "petition to open granted", "value" => $value{"petition to open granted"}});
push(@{$r{links}}, {"source" => "petition to open", "target" => "petition to open denied", "value" => $value{"petition to open denied"}});
push(@{$r{links}}, {"source" => "petition to open granted", "target" => "hearing date", "value" => $value{"petition to open granted"}});
push(@{$r{links}}, {"source" => "hearing date", "target" => "judgment for defendant", "value" => $value{"judgment for defendant"}});
push(@{$r{links}}, {"source" => "hearing date", "target" => "judgment for plaintiff", "value" => $value{"judgment for plaintiff"}});
push(@{$r{links}}, {"source" => "hearing date", "target" => "JBA", "value" => $value{"JBA"}});
push(@{$r{links}}, {"source" => "judgment for plaintiff", "target" => "any judgment", "value" => $value{"judgment for plaintiff"}});
push(@{$r{links}}, {"source" => "JBA", "target" => "any judgment", "value" => $value{"JBA"}});
#push(@{$r{links}}, {"source" => "judgment for defendant", "target" => "any judgment", "value" => $value{"judgment for defendant"}});
push(@{$r{links}}, {"source" => "petition to open denied", "target" => "any judgment", "value" => $value{"petition to open denied"}});
push(@{$r{links}}, {"source" => "default judgment", "target" => "any judgment", "value" => $value{"default judgment"} - $value{"petition to open"}});
push(@{$r{links}}, {"source" => "any judgment", "target" => "judgment satisfied", "value" => $value{"judgment satisfied no writ"}});
push(@{$r{links}}, {"source" => "writ of possession", "target" => "judgment satisfied", "value" => $value{"judgment satisfied after writ"}});
push(@{$r{links}}, {"source" => "alias writ", "target" => "judgment satisfied", "value" => $value{"judgment satisfied after alias writ"}});
push(@{$r{links}}, {"source" => "alias writ served", "target" => "judgment satisfied", "value" => $value{"judgment satisfied after alias writ served"}});
push(@{$r{links}}, {"source" => "any judgment", "target" => "writ of possession", "value" => $value{"writ of possession"}});
push(@{$r{links}}, {"source" => "writ of possession", "target" => "alias writ", "value" => $value{"alias writ"}});
push(@{$r{links}}, {"source" => "alias writ", "target" => "alias writ served", "value" => $value{"alias writ served"}});



my $result = encode_json(\%r);
$redis->set($redis_key => $result);
if ($ltconditions =~ /year=2019/){
  $redis->expire($redis_key => 60*60*24);
}
else{
  $redis->expire($redis_key => 60*60*24*30);
}
print $q->header('text/json');
print $result;
