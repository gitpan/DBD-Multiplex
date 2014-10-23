#########1#########2#########3#########4#########5#########6#########7#########8

{ #========================================================== DBD ===

package DBD::Multiplex;

require DBI;

$DBI::dbi_debug = 1;

@EXPORT = ();
$VERSION = substr(q$Revision: 1.7 $, 9,-1) -1;

# $Id: Multiplex.pm,v 1.7 2001/07/12 00:01:01 timbo Exp $
#
# Copyright (c) 1999, Tim Bunce && Thomas Kishel
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

use strict;

use vars qw($VERSION $drh $err $errstr $sqlstate);

$drh = undef;	# Holds driver handle once it has been initialized.
$err = 0;	# Holds error code for $DBI::err.
$errstr = '';	# Holds error string for $DBI::errstr.
$sqlstate = '';	# Holds SQL state for $DBI::state.

#########################################
# The driver handle constructor.
#########################################

sub driver {
	return $drh if ($drh);
	my ($class, $attr) = @_;

	$class .= "::dr";
	
	# $drh is not scoped with 'my', 
	# since we use it above to prevent multiple drivers.
	
	($drh) = DBI::_new_drh ($class, {
		'Name' => 'Multiplex',
		'Version' => $VERSION,
		'Attribution' => 'DBD Multiplex by Tim Bunce && Thomas Kishel',
	});
	
	return $drh;
}

########################################
# Function for calling a method for each child handle of a parent handle.
# The parent handle is one of 'our' database or statement handles.
# Each of the child handles is a 'native' database or statement handle.
# -- called inside AUTOLOAD --
########################################

sub mx_method_all {
	# Remember that shift modifies the parameter list.
	my ($method, $parent_handle) = (shift, shift);

	my ($exit_mode, %modes, %multiplex_options, $results, $errors, $result);
	
	$exit_mode  = $parent_handle->{'mx_exit_mode'};

#	# TK Note: 
#	# do() is a method of a database handle, not a statement handle.
	if ($method eq 'do' or $method eq 'disconnect') {
		$parent_handle->{'Statement'} = $_[0];
	}
	
	# Override both the default exit_mode,
	# and the exit_mode attribute stored in the parent handle,
	# when multiplexing the following:
	%modes = (
		'STORE'		=> 'first_error',
		'FETCH'		=> 'first_error',
		'finish'	=> 'last_result',
		'disconnect'	=> 'last_result');

	$exit_mode = $modes{$method} if ($modes{$method});

	%multiplex_options = (
		'parent_handle' => $parent_handle, 
		'exit_mode' => $exit_mode);
	
	($results, $errors) = &DBD::Multiplex::mx_do_calls (
		$method, 
		wantarray, 
		\%multiplex_options, 
		@_);
	
	# find valid result
	for (@$results) { 
		$result = $_, last if defined $_->[0];
	}

#	# EP Note:
#	# original code: only takes the first result
#	# $result = $results->[0];

	return $result->[0] unless (wantarray);
	return @$result;
}

########################################
# 'Bottom-level' support function to multiplex the calls.
# See the documentation for information about $exit_mode.
# Currently the 'last_result' exit_mode is automagic.	
########################################

sub mx_do_calls {
	# Remember that shift modifies the parameter list.
	my ($method, $wantarray, $multiplex_options) = (shift, shift, shift);

	# @errors is a sparse array paralleling $results[0..n]
	my ($parent_handle, $handle_list, $id_list, $error_proc, $exit_mode);
	my ($child_handle, $child_number, @results, @errors);
	my ($child_err, $child_errstr, $statement);

	$parent_handle = $multiplex_options->{'parent_handle'} || die;
	$handle_list = $parent_handle->{'mx_handle_list'} || die;
	$id_list = $parent_handle->{'mx_id_list'};
	$exit_mode = $multiplex_options->{'exit_mode'} || 'first_error';
	$error_proc = $parent_handle->{'mx_error_proc'};

	$parent_handle->trace_msg("mx_do_calls $method for " .
		join(", ", map{defined $_?$_:''} @$handle_list) . "\n");

	$child_number = 0;

	# EP If master dsn is specified, and current statement is a
	# modification operation, make sure this is done on the master:

#	# EP Note: 
#	# If ($method eq 'do' || $method eq 'execute' and
#	# the above condition is wrong, because then _any_ prepare()
#	# will definitely go to second condition.

	if  (
		$statement = $parent_handle->{'Statement'} and 
		&DBD::Multiplex::mx_is_modify_statement(\$statement) and
		$parent_handle->{'mx_master_id'}) {
		
#		# TK Note:
#		# Consider finding once and storing rather than finding each time.

		# Loop to find the master handle.
		for (@$id_list) { 
			last if $_ eq $parent_handle->{'mx_master_id'};
			push @results, [undef];
			$child_number++; 
		}
		
		$child_handle = $handle_list->[$child_number];
		$results[$child_number] = ($wantarray) 
			? [ $child_handle->$method(@_) ]
			: [ scalar $child_handle->$method(@_) ];

		if ($child_err = $child_handle->err) {
			$child_errstr = $child_handle->errstr;
			$errors[$child_number] = [$child_err, $child_errstr];
			if ($parent_handle) {
				&DBI::set_err($parent_handle, $child_err, $child_errstr);
			}
# 			# TK Note: 
#			# Consider passing DBI error to error_proc.
			if ($error_proc) {
				&$error_proc->(${$id_list}[$child_number], $statement);
			}
		}

	} else {

		foreach $child_handle (@$handle_list) {

			$parent_handle->trace_msg("mx_do_calls $method for statement " .
				"$statement against child no. $child_number\n") if $statement;

			# Here, the actual method being multiplexed is being called.
			push @results, ($wantarray) 
				? [ $child_handle->$method(@_) ]
				: [ scalar $child_handle->$method(@_) ];

			if ($child_err = $child_handle->err) {
				$child_errstr = $child_handle->errstr;
				$errors[@results - 1] = [$child_err, $child_errstr];
				if ($parent_handle) {
					&DBI::set_err($parent_handle, $child_err, $child_errstr);
				}
				if ($error_proc) {
#					# TK Note: Consider above EP Note.
					if (($method eq 'do') || ($method eq 'execute')) {
						$statement = $parent_handle->{'Statement'};
						if (&DBD::Multiplex::mx_is_modify_statement(\$statement)) {
							&$error_proc(${$id_list}[$child_number], $statement);
						}
					}
				}
				last if ($exit_mode eq 'first_error');
			} else {
				last if ($exit_mode eq 'first_success');
			}

			$child_number = $child_number + 1;
		}

	}
	
	return (\@results, \@errors);
}

########################################
# Identify if the statement modifies data in the datasource.
# EP Added CREATE and DROP.
# TK Consider adding INTO.
########################################

sub mx_is_modify_statement {
	my ($statement) = @_;
	
	return ($$statement =~ /INSERT |UPDATE |DELETE |CREATE |DROP /i);
}

########################################
# Example statement error logging mechanism.
# TK Note: 
# Consider passing DBI error to error_proc.
########################################

sub mx_error_subroutine {
	my ($datasource, $sql) = @_;
	
	print STDERR "ERROR: $datasource\n";
	print STDERR "$sql\n\n";
	
	return 1;
}

} #====================================================== END DBD ===

{ #======================================================= DRIVER ===

package DBD::Multiplex::dr;
$imp_data_size = 0;

########################################
# The database handle constructor.
# This function cannot be called using mx_method_all.
########################################

sub connect { 
	my ($drh, $dsn, $user, $auth, $attr) = @_;
	
	my (@dsn_list, $dbh, @dbh_list, $mx_id, @mx_id_list);
	my ($connect_mode, $exit_mode, $error_proc, $this);
	my ($dsn_count, @dsn_order, $dsn_number);

	# Retrieve the DSNs from the $dsn parameter.
	@dsn_list = split (/\|/, $dsn);
	
	# Add the DSNs from the attribute hashref parameter.
	foreach (@{$$attr{'mx_dsns'}}) {
		push (@dsn_list, $_);
	}
	
	$dsn_count = @dsn_list;

	# connect_mode decides what to do with DBI->connect errors.
	# exit_mode decides when to exit the foreach loop.
	# error_proc is a code reference to execute in case of an execute error.
	$connect_mode = ($$attr{'mx_connect_mode'} || 'report_errors');
	$exit_mode = $$attr{'mx_exit_mode'} || 'first_error';
	$error_proc = $$attr{'mx_error_proc'} || '';

	# 'first_success_random' exit_mode is implemented only at connect time.
	# Afterwards, revert to 'first_success' exit_mode.
	
#	# TK Note: 
#	# Trying to implement randomness after this point fails.
#	# This needs careful consideration.
#	# Consider creating a new parameter; 
#	# changing parameter into a connect_mode;
#	# or rewriting randomness to work correctly at lower levels.
	if ($exit_mode eq 'first_success_random') {
		@dsn_order = &mx_rand_list($dsn_count - 1);	 
		$attr->{'mx_exit_mode'} = 'first_success';
	} else {
		@dsn_order = (0..$dsn_count);
	}
		
	# Connect to each dsn in the dsn_list.
	for ($dsn_number = 0; $dsn_number < $dsn_count; $dsn_number++) {
		$dsn = $dsn_list[$dsn_order[$dsn_number]];

		# Retrieve the datasource id for use by the error_proc.
		# Remove the datasource id from the driver name.
		# There is no standard for the text following the driver name.
		# Each driver is free to use whatever syntax it wants.
		$dsn =~ /mx_id=(\w+)/i;
		$mx_id = $1;
		$dsn =~ s/;?mx_id=$mx_id;?/;/;
		$dsn =~ s/^;|;$//;

		$dbh = DBI->connect($dsn, $user, $auth, $attr);
		if ($dbh) {
			push (@dbh_list, $dbh);
			push (@mx_id_list, $mx_id);
		} else {
			if ($connect_mode eq 'ignore_errors') {
#				# TK Note:
#				# Consider overriding 'ignore_errors' if this is the mx_master_id.
			
#				# TK Note: 
#				# This needs careful consideration.
#				# Consider implemening a blank handle, reconnect,
#				# process queue, and then reintegrate into the pool after an outage.
				# $dbh = DBI::_new_dbh($drh, {});
				# push (@dbh_list, $dbh);
				# push (@mx_id_list, $mx_id);
			} else {
				return DBI::set_err($drh, $DBI::err, $DBI::errstr);
			}
		}
		
	}
	
	$this = DBI::_new_dbh ($drh, {
		'Name' => [@dsn_list],
		'User' => $user,
		'mx_handle_list' => [@dbh_list],
		'mx_id_list' => [@mx_id_list],
		'mx_master_id' => $attr->{'mx_master_id'},
		'mx_exit_mode' => $attr->{'mx_exit_mode'},
		'mx_error_proc' => $error_proc,
	});

	return $this;
}

########################################
# Required by the DBI.
########################################

sub disconnect_all {
	
}

########################################
# Required by the DBI.
########################################

sub DESTROY {
	undef;
}

########################################
# A random list of numbers.
########################################
sub mx_rand_list {
	my (@input) = (0..$_[0]);
	my (@output);
	
	srand(time() ^ ($$ + ($$ << 15)));
	push(@output, splice (@input, rand(@input), 1)) while (@input);
	
	return @output;
}

} #=================================================== END DRIVER ===

{ #===================================================== DATABASE ===

package DBD::Multiplex::db; 
	$imp_data_size = 0;
	use strict;

########################################
# The statement handle constructor. 
# This function calls mx_do_calls and therefore cannot be called using mx_method_all.
# TK Note:
# Consider the interaction between do, prepare, execute, and mx_error_proc.
########################################

sub prepare {
	# Remember that shift modifies the parameter list.
	my ($dbh) = shift;
	my ($statement, $attr) = @_;

	my ($parent_id_list, $parent_error_proc, $parent_exit_mode, $parent_master_id);
	my ($exit_mode, %multiplex_options, $results, $errors, $outer, $sth);

	$parent_id_list = $dbh->{'mx_id_list'};
	$parent_master_id = $dbh->{'mx_master_id'};
	$parent_exit_mode = $dbh->{'mx_exit_mode'};
	$parent_error_proc = $dbh->{'mx_error_proc'};

	# The user can set the exit_mode of a new or existing database handle.
	# Otherwise, parse the SQL statement to determine the exit_mode.
	if ($parent_exit_mode) {
		$exit_mode = $parent_exit_mode;
	} else {
		$exit_mode = &DBD::Multiplex::db::mx_default_statement_mode(\$statement);
	}

	# Don't forget this!
	$dbh->{'Statement'} = $statement;

	%multiplex_options = (
		'parent_handle' => $dbh,
		'exit_mode' => $exit_mode);

	($results, $errors) = &DBD::Multiplex::mx_do_calls (
		'prepare', 
		wantarray, 
		\%multiplex_options, 
		@_);

	return if (@$errors);

	# Assign the @results of the multiple prepare calls, 
	# executed against each of the $dbh's children handles, 
	# to an array of children stored in the statement handle.
	# $sth is a reference to the inner hash (used by the driver).
	# $outer is a reference to the outer hash (used by the user of the DBI).
	($outer, $sth) = DBI::_new_sth ($dbh, {
		'Statement' => $statement,
		'mx_handle_list' => [map {$_->[0]} @$results],
		'mx_id_list' => $parent_id_list,
		'mx_master_id' => $parent_master_id,
		'mx_exit_mode' => $parent_exit_mode,
		'mx_error_proc' => $parent_error_proc,
	});

	return $outer;
}


########################################
# Some attributes are stored in the parent handle.
# some in each of the children handles.
# This function uses and therefore cannot be called using mx_method_all.
########################################

sub STORE {
	my ($dbh, $attr, $val) = @_;

	 if ($attr =~ /^mx_(.+)/) {
		if ($1 eq uc($1)) {
			return $dbh->SUPER::STORE($attr, $val);
		} else {
			return $dbh->{$attr} = $val;
		}
	}

	# Store the attribute in each of the children handles.
	return &DBD::Multiplex::mx_method_all('STORE', @_);
}

########################################
# Some attributes are stored in the parent handle.
# some in each of the children handles.
# This function uses and therefore cannot be called using mx_method_all.
########################################

sub FETCH {
	my ($dbh, $attr) = @_;

	if ($attr =~ /^mx_(.+)/) {
		if ($1 eq uc($1)) {
			return $dbh->SUPER::FETCH($attr);
		} else {
			return $dbh->{$attr};
		}
	}

	# Fetch the attribute from one of the children handles.
	return &DBD::Multiplex::mx_method_all('FETCH', @_);
}

########################################
# TK Note:
# Replace this with dynamic information from updated DBI.
# Needs expanding manually in the short term.
# Look at %DBI_IF in DBI.pm for details.
########################################

use subs qw(
		do disconnect ping tables table_info
		commit rollback
		selectall_arrayref selectall_array selectcol_arrayref
		);

######################################## 
# Call the multiplexing code for each of the database methods listed above.
########################################

sub AUTOLOAD {
	my ($method, @results);
	
	$method = $DBD::Multiplex::db::AUTOLOAD;
	$method =~ s/^DBD::Multiplex::db:://;
		
	# Two levels down, the actual method being multiplexed is being called.
	@results = (wantarray)
		? ( &DBD::Multiplex::mx_method_all($method, @_) )
		: ( scalar &DBD::Multiplex::mx_method_all($method, @_) );

	return $results[0] unless (wantarray);
	return @results;
}

########################################
# The default behaviour is to not multiplex simple select statements.
# The resulting statement handle then contains only one child handle,
# automatically resulting in subsequent methods executed against the 
# statement handle to use 'first_success' mode.
#
# TK Note:
# Consider a more efficient grep, or at least one similar in syntax to mx_is_modify_statement.
########################################

sub mx_default_statement_mode {
	my ($statement) = @_;
	my ($result);
	
	if (($$statement !~ /INTO/i) && ($$statement =~ /^SELECT/i)) {
		$result = 'first_success';
	}
	
	return $result;
}

} #================================================= END DATABASE ===

{ #==================================================== STATEMENT ===

package DBD::Multiplex::st; 
$imp_data_size = 0;
use strict;
	
########################################
# Some attributes are stored in the parent handle.
# some in each of the children handles.
# This function uses and therefore cannot be called using mx_method_all.
########################################

sub STORE {
	my ($sth, $attr, $val) = @_;

	if ($attr =~ /^mx_(.+)/) {
		if ($1 eq uc($1)) {
			return $sth->SUPER::STORE($attr, $val) if ($1 eq uc($1));
		} else {
			return $sth->{$attr} = $val;
		}
	 }

	# Store the attribute in each of the children handles.
	return &DBD::Multiplex::mx_method_all('STORE', @_);
}

########################################
# Some attributes are stored in the parent handle.
# some in each of the children handles.
# This function uses and therefore cannot be called using mx_method_all.
########################################

sub FETCH {
	my ($sth, $attr) = @_;

	if ($attr =~ /^mx_(.+)/) {
		if ($1 eq uc($1)) {
			return $sth->SUPER::FETCH($attr);
		} else {
			return $sth->{$attr};
		}
	}

	# Fetch the attribute from each of the children handles.
	return &DBD::Multiplex::mx_method_all('FETCH', @_);
}

########################################
# TK Note:
# Replace this with dynamic info from updated DBI.
# Needs expanding manually in the short term.
# Look at %DBI_IF in DBI.pm for details.
########################################

use subs qw(
		fetch fetchrow 
		fetchrow_array fetchrow_arrayref fetchrow_hashref
		bind_param bind_col bind_columns
		rows execute finish
		);

########################################
# Call the multiplexing code for each of the statement methods listed above.
########################################

sub AUTOLOAD {
	my ($method, @results);
	
	$method = $DBD::Multiplex::st::AUTOLOAD;
	$method =~ s/^DBD::Multiplex::st:://;
	
	# Two levels down, the actual method being multiplexed is being called.
	@results = (wantarray) 
		? ( &DBD::Multiplex::mx_method_all($method, @_) )
		: ( scalar &DBD::Multiplex::mx_method_all($method, @_) );

	return $results[0] unless (wantarray);
	return @results;
}

} #================================================ END STATEMENT ===

1;

__END__

=head1 NAME

DBD::Multiplex - A multiplexing driver for the DBI.

=head1 SYNOPSIS

 use strict;

 use DBI;

 my ($dsn1, $dsn2, $dsn3, $dsn4, %attr);

 # Define four databases, in this case, four Postgres databases.
 
 $dsn1 = 'dbi:Pg:dbname=aaa;host=10.0.0.1;mx_id=db-aaa-1';
 $dsn2 = 'dbi:Pg:dbname=bbb;host=10.0.0.2;mx_id=db-bbb-2';
 $dsn3 = 'dbi:Pg:dbname=ccc;host=10.0.0.3;mx_id=db-ccc-3';
 $dsn4 = 'dbi:Pg:dbname=ddd;host=10.0.0.4;mx_id=db-ddd-4';

 # Define a callback error handler.
 
 sub MyErrorProcedure {
	my ($datasource, $sql) = @_;
	my ($filepath, $extension) = ('/tmp/', '.txt');
	open (DSQL, ">>$filepath$datasource$extension");
	print (DSQL "$sql\n");
	close (DSQL);
	return 1;
 }

 # Define the pool of datasources.
 
 %attr = (
	'mx_dsns' => [$dsn1, $dsn2, $dsn3, $dsn4],
	'mx_master_id' => 'db-aaa-1',
	'mx_connect_mode' => 'ignore_errors',
	'mx_exit_mode' => 'first_success',
	'mx_error_proc' => \&MyErrorProcedure(),
 );

 # Connect to all four datasources.
 
 $dbh = DBI->connect("dbi:Multiplex:", 'username', 'password', \%attr); 

 # See the DBI module documentation for full details.

=head1 DESCRIPTION

DBD::Multiplex is a Perl module which works with the DBI
to provide access to multiple datasources using singular DBI calls.

The most obvious use of this module is to mirror the contents
of one datasource using a set of alternate datasources.

One typical methodology is to write to all datasources, 
but read from only from one datasource.

Basically, DBD::Multiplex database and statement handles
are parents that store multiple child handles, one for each datasource.

=head1 COMPATIBILITY

A goal of this module is to be compatible with DBD::Proxy / DBI::ProxyServer.
Currently, the 'mx_error_proc' feature generates errors regarding the storage
of CODE references within the Storable module used by RPC::PlClient
which in turn is used by DBD::Proxy. Yet it works.

=head1 CONNECTING TO THE DATASOURCES

Multiple datasources are specified in the either the DSN parameter of
the DBI->connect() function (separated by the '|' character), 
or in the 'mx_dsns' key/value pair (as an array reference) of 
the \%attr hash parameter.

To use the mx_error_proc feature, you must include a unique 
'mx_id' key/value pair in the DSN of each datasource.

=head1 SPECIFIC ATTRIBUTES

The following specific attributes can be set when connecting:

=over 4

=item B<mx_dsns>

An array reference of DSN strings. 

=item B<mx_master_id>

Specifies which mx_id will be used as the master server for a
master/slave one-way replication scheme.

=item B<mx_connect_mode>

Options available or under consideration:

B<report_errors>

A failed connection to any of the data sources will generate a DBI error.
This is the default.

B<ignore_errors>

Failed connections are ignored, forgotten, and therefore, unused.

=item B<mx_exit_mode>

Options available or under consideration:
 
B<first_error>

Execute the requested method against each child handle, stopping 
after the first error, and returning the all of the results.
This is the default.

B<first_success>

Execute the requested method against each child handle, stopping after 
the first successful result, and returning only the successful result.
Most appropriate when reading from a set of mirrored datasources.

B<first_success_random>

Randomly reorders the list of DSNs, and then connects to them in that order.
Then switches to B<first_success> mode. 
You can redefine mx_exit_mode after connecting.

	 $dbh->{'mx_exit_mode'} = 'last_result';
	
B<last_result>

Execute the requested method against each child handle, not stopping after 
any errors, and returning all of the results.

B<last_result_most_common>

Execute the requested method against each child handle, not stopping after 
the errors, and returning the most common result (eg three-way-voting etc).
Not yet implemented.

=item B<mx_error_proc>

A reference to a subroutine which  will be executed whenever a 
datasource fails to execute a SQL statement. It will be passed 
the 'mx_id' of the datasource, and the SQL statement.

Define your own subrouine and pass a reference to it, 
or pass a reference to the default error_proc:

	\&DBD::Multiplex::mx_error_subroutine().

To use this feature, you must identify each datasource with a mx_id. 

=back

In some cases, the exit mode will depend on the method being called.
For example, this module will always execute $dbh->disconnect() calls 
against each child handle.
 
In others, the default will be used, unless the user of the DBI  
specified the 'mx_exit_mode' when connecting, or later changed 
the 'mx_exit_mode' attribute of a database or statement handle. 

=head1 USAGE EXAMPLE

Here's an example of using DBD::Multiplex with MySQL's replication scheme. 
MySQL supports one-way replication, which means we run a server as the master 
server and others as slaves which catch up any changes made on the master. 
Any READ operations then may be distributed among them (master and slave(s)), 
whereas any WRITE operation must B<only> be directed toward the master. 
Any changes happened on slave(s) will never get synchronized to other servers. 
More detailed instructions on how to arrange such setup can be found at:

http://www.mysql.com/documentation/mysql/bychapter/manual_Replication.html

Now say we have two servers, one at 10.0.0.1 as a master, and one at 
10.0.0.9 as a slave. The DSN for each server may be written like this:

 my (@dsns) = qw{
	dbi:mysql:database=test;host=10.0.0.1;mx_id=masterdb
	dbi:mysql:database=test;host=10.0.0.9;mx_id=slavedb
 };

Here we choose easy-to-remember C<mx_id>s: masterdb and slavedb.
You are free to choose alternative names, for example: mst and slv. 
Then we create the DSN for DBD::Multiplex by joining them, using the 
pipe character as separator:

 my ($dsn) = 'dbi:Multiplex:' . join('|', @dsns);
 my ($user) = 'username';
 my ($pass) = 'password';

As a more paranoid practice, configure the 'user's permissions to
allow only SELECTs on the slaves.

Next, we define the attributes which will affect DBD::Multiplex behaviour:

 my (%attr) = (
	'mx_exit_mode' => 'first_success_random',
	'mx_master_id' => 'masterdb',
 );

These attributes are required for MySQL replication support:

We set C<mx_exit_mode> to 'first_success_random' which will make
DBD::Multiplex shuffle the DSN list order prior to connect,
and afterwards revert to 'first_success'.

The C<mx_master_id> attribute specifies which C<mx_id> will be recognized
as the master. In our example, this is set to 'masterdb'. This attribute will
ensure that every WRITE operation will be executed only on the master server.
Finally, we call DBI->connect():

 $dbh = DBI->connect($dsn, $user, $pass, \%attr) or die $DBI::errstr;

=head1 AUTHORS AND COPYRIGHT

Copyright (c) 1999, Tim Bunce && Thomas Kishel

While I defer to Tim Bunce regarding the majority of this module,
feel free to contact me for more information:

	Thomas Kishel
	Larson Texts, Inc.
	1760 Norcross Road
	Erie, PA 16510
	tkishel@tdlc.com
	814-461-8900

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
