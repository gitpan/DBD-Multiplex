#!/usr/bin/perl

use strict;

use DBI;
use DBD::Pg;
use DBD::Multiplex;

my ($dsn1, $dsn2, $u, $p, $dsns, %attr, $dbh, $sth, $hash_ref, @hash_refs);

#---------------------------------------#
$dsn1 = 'dbi:Pg:dbname=db-aaa-1;host=10.0.0.1';
$dsn2 = 'dbi:Pg:dbname=db-bbb-2;host=10.0.0.2';
$u = 'dbusername';
$p = 'dbpassword';
#---------------------------------------#

$dsns = join ('|', ($dsn1,$dsn2));
%attr = (
	'mx_connect_mode' => 'report_errors',
	'mx_exit_mode' => 'last_result',
);

#---------------------------------------#
# connect and write to all databases
#---------------------------------------#

$dbh = DBI->connect("dbi:Multiplex:$dsns", $u, $p, \%attr);
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $dbh) {
	print "Cannot connect to databases: $DBI::errstr\n";
}

$sth = $dbh->prepare("update users set u_password = 'guess' where u_id = 'person'");
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);

$sth->execute;
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
$sth->finish;

$sth = $dbh->prepare("select * from users where u_id = 'person'");
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $sth) {
	print "Statement preparation failed: $DBI::errstr\n";
}

$sth->execute;
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);

while ($hash_ref = $sth->fetchrow_hashref) {
	print "DB0 $$hash_ref{'u_id'} $$hash_ref{'u_password'} \n";
}

$sth->finish;
$dbh->disconnect;

#---------------------------------------#
# connect to first database and read
#---------------------------------------#

$dbh = DBI->connect("$dsn1", $u, $p);
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $dbh) {
	print "Cannot connect to database: $DBI::errstr\n";
}
$dbh->{'ChopBlanks'} = 1;

$sth = $dbh->prepare("select * from users where u_id = 'person'");
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $sth) {
	print "Statement preparation failed: $DBI::errstr\n";
}

$sth->execute;
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);

while ($hash_ref = $sth->fetchrow_hashref) {
	print "DB1 $$hash_ref{'u_id'} $$hash_ref{'u_password'} \n";
}

$sth->finish;
$dbh->disconnect;

#---------------------------------------#
# connect to second database and read
#---------------------------------------#

$dbh = DBI->connect("$dsn2", $u, $p);
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $dbh) {
	print "Cannot connect to database: $DBI::errstr\n";
}
$dbh->{'ChopBlanks'} = 1;

$sth = $dbh->prepare("select * from users where u_id = 'person'");
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $sth) {
	print "Statement preparation failed: $DBI::errstr\n";
}

$sth->execute;
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);

while ($hash_ref = $sth->fetchrow_hashref) {
	print "DB1 $$hash_ref{'u_id'} $$hash_ref{'u_password'} \n";
}

$sth->finish;
$dbh->disconnect;

#---------------------------------------#
# connect to all databases and read
#---------------------------------------#

$dbh = DBI->connect("dbi:Multiplex:$dsns", $u, $p, \%attr);
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $dbh) {
	print "Cannot connect to databases: $DBI::errstr\n";
}
$dbh->{'ChopBlanks'} = 1;

$sth = $dbh->prepare("select * from users where u_id = 'person'");
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);
if (! defined $sth) {
	print "Statement preparation failed: $DBI::errstr\n";
}

$sth->execute;
print "Errors: $DBI::err, $DBI::errstr\n" if ($DBI::err || $DBI::errstr);

@hash_refs = $sth->fetchrow_hashref;

foreach (@hash_refs) {
        print "DBS $$_{'u_id'} $$_{'u_password'} \n";
}

$sth->finish;
$dbh->disconnect; 

1;
