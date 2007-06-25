use DBI;
use DBI::DBD;

use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence the contents of the Makefile that is written.

WriteMakefile (
	dbd_edit_mm_attribs( 
		{
			'NAME'		=>	'DBD::Multiplex',
			'VERSION_FROM'	=>	'Multiplex.pm',
			'INC'		=>	$DBI_INC_DIR,
			'dist'		=>	{ COMPRESS => gzip, SUFFIX => '.gz'},
		},
		{
			create_pp_tests	=>	1
		}
	)
);

package MY;

sub postamble { return main::dbd_postamble(@_); }

sub libscan {
	my ($self, $path) = @_;
	
	($path =~ m/\~$/) ? undef : $path;
}
