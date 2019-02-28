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
  $ltconditions = "lt.year=2016";
}
if (defined($q->param('rentstart')) && defined($q->param('rentend'))){
  if (int($q->param('rentstart')) != 0){
    $ltconditions .= " and monthly_rent_amount >= " . $q->param('rentstart');
  }
  if (int($q->param('rentend')) != 2000){
    $ltconditions .= " and monthly_rent_amount < " . $q->param('rentend');
  }
}
if ($q->param('zip')){
  $ltconditions .= " and zip='" . $q->param('zip') . "'";
}
foreach my $key ("defendant_represented", "plaintiff_represented"){
  if ($q->param($key) eq "True"){
    $ltconditions .= " and $key";
  }
  elsif ($q->param($key) eq "False"){
    $ltconditions .= " and not $key";
  }
}

print STDERR "Conditions are $ltconditions\n";

my $redis_key = 'sankeypa:' . $ltconditions;

my $cache_result = $redis->get($redis_key);
if ($cache_result){
  print $q->header('text/json');
  print $cache_result;
  exit;
}

my $dref = DBI->connect('dbi:Pg:dbname=eviction;host=localhost', 'jpyle', 'foobar', {AutoCommit => 1}) or croak DBI->errstr;

my %value;
my %query_list = (
		  "case filed" => "select count(distinct a.id) from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) where a.eventtype='CF'",
		  "withdrawn" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='WD' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('JFD', 'JFP', 'SET')) as aa;",
		  "appeal filed" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (b.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and b.eventtype='JFP' and c.eventtype in ('APM', 'APP') except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "appeal successful" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (b.id=c.id and c.eventdate > b.eventdate) inner join paevents as d on (a.id=d.id and d.eventdate > c.eventdate) where a.eventtype='CF' and b.eventtype='JFP' and c.eventtype in ('APM', 'APP') and d.eventtype in ('APMS', 'APPS') except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "appeal failed" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (b.id=c.id and c.eventdate > b.eventdate) inner join paevents as d on (a.id=d.id and d.eventdate > c.eventdate) where a.eventtype='CF' and b.eventtype='JFP' and c.eventtype in ('APM', 'APP') and d.eventtype in ('APMF', 'APPF') except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "hearing date" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('JFD', 'JFP') group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		  "judgment for defendant" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='JFD' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		  "judgment for plaintiff" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='JFP' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		  "settled" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='SET' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "settled" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join paevents as b on (a.id=b.id and b.eventdate > a.eventdate) where a.eventtype='CF' and b.eventtype='SET' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "judgment satisfied" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='JFP' group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'SAT' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='WD') as aa;",
		  "order of possession" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='JFP' group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'OP' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		  "order of possession served" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='JFP' group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join paevents as d on (a.id=d.id and d.eventdate >= c.eventdate) where a.eventtype='CF' and c.eventtype like 'OP' and d.eventtype='OPS' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		  "judgment satisfied no order" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('JFP') group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) where a.eventtype='CF' and c.eventtype like 'SAT' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'OP', 'OPS', 'SET')) as aa;",
		  "judgment satisfied after order" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype='JFP' group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join paevents as d on (a.id=d.id and d.eventdate >= c.eventdate) where a.eventtype='CF' and c.eventtype like 'OP' and d.eventtype like 'SAT' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'OPS', 'SET')) as aa;",
		  "judgment satisfied after order served" => "select count(distinct id) from (select a.id from paevents as a inner join ltcasessum as lt on (a.id=lt.id and $ltconditions) inner join (select paevents.id, max(eventdate) as eventdate from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('JFP') group by paevents.id) as b on (a.id=b.id and b.eventdate > a.eventdate) inner join paevents as c on (a.id=c.id and c.eventdate > b.eventdate) inner join paevents as d on (a.id=d.id and d.eventdate >= c.eventdate) inner join paevents as e on (a.id=e.id and e.eventdate >= d.eventdate) where a.eventtype='CF' and c.eventtype like 'OP' and d.eventtype='OPS' and e.eventtype like 'SAT' except select paevents.id from paevents inner join ltcasessum as lt on (paevents.id=lt.id and $ltconditions) where eventtype in ('WD', 'SET')) as aa;",
		 );

my %r = (nodes => [], links => []);
my $start_time = time();
foreach my $key (sort keys %query_list){
  my $query_string = $query_list{$key};
  if ($key ne "appeal filed" && $key ne "appeal successful" && $key ne "appeal failed" && $key ne "judgment satisfied after order" && $key ne "judgment satisfied after order served" && $key ne "judgment satisfied no order"){
    if ($key eq "withdrawn"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posX" => 200, "posY" => 0});
    }
    elsif ($key eq "settled"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posX" => 400, "posY" => 15});
    }
    elsif ($key eq "judgment for defendant"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 15, "posXrel" => "judgment for plaintiff"});
    }
    elsif ($key eq "judgment satisfied"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 0});
    }
    elsif ($key eq "hearing date"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYbot" => 700});
    }
    elsif ($key eq "judgment for plaintiff"){
      push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYbot" => 700});
    }
    # elsif ($key eq "default judgment"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posX" => 300, "posYbot" => 700});
    # }
    # elsif ($key eq "hearing date"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 70});
    # }
    # elsif ($key eq "petition to open"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment"});
    # }
    # elsif ($key eq "petition to open granted"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment", "posYoff" => -40});
    # }
    # elsif ($key eq "petition to open denied"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posYrel" => "default judgment", "posYoff" => -20});
    # }
    # elsif ($key eq "JBA"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 170});
    # }
    # elsif ($key eq "judgment for defendant"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 10, "posXrel" => "judgment for plaintiff"});
    # }
    # elsif ($key eq "judgment for plaintiff"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 50});
    # }
    # elsif ($key eq "judgment satisfied"){
    #   push(@{$r{nodes}}, {"id" => $key, "name" => $key, "posY" => 10});
    # }
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
push(@{$r{links}}, {"source" => "case filed", "target" => "settled", "value" => $value{"settled"}});
push(@{$r{links}}, {"source" => "case filed", "target" => "hearing date", "value" => $value{"hearing date"}});
push(@{$r{links}}, {"source" => "hearing date", "target" => "judgment for defendant", "value" => $value{"judgment for defendant"}});
push(@{$r{links}}, {"source" => "hearing date", "target" => "judgment for plaintiff", "value" => $value{"judgment for plaintiff"}});
push(@{$r{links}}, {"source" => "judgment for plaintiff", "target" => "judgment satisfied", "value" => $value{"judgment satisfied no order"}});
push(@{$r{links}}, {"source" => "judgment for plaintiff", "target" => "order of possession", "value" => $value{"order of possession"}});
push(@{$r{links}}, {"source" => "order of possession", "target" => "judgment satisfied", "value" => $value{"judgment satisfied after order"}});
push(@{$r{links}}, {"source" => "order of possession", "target" => "order of possession served", "value" => $value{"order of possession served"}});
push(@{$r{links}}, {"source" => "order of possession served", "target" => "judgment satisfied", "value" => $value{"judgment satisfied after order served"}});

my $result = encode_json(\%r);
$redis->set($redis_key => $result);
print $q->header('text/json');
print $result;
