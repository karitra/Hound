#!/bin/env perl -w
# 
# Tiny-Silly robot for job applying
#
# 2012. Copyleft. Alex Karev
#

=pod Job hash structure

Jobs hash used within the robot has same keys as jobs.perl.org/job/#num# fields plus
 offer_id,
 firm_id,
 should_apply

=cut 

use strict;
use warnings;
use utf8;

map {binmode $_, ':utf8' }  (*STDOUT, *STDERR);

use feature qw/
	say
	state
/;

use constant IS_DBG_MODE => 1;

sub dbg(&)
{
	my $f = shift;

	if (IS_DBG_MODE)
		{ $f->(@_); }
	else
		{         ; }
}

package JPL;
#use HTML::Parser;
#use HTML::TokeParser;
use LWP::Simple;

# Globals & constants
use constant PERL_JOBS_URL => 'http://jobs.perl.org';
use constant { # Telecommute mode
	OM_NONE => '',
	OM_YES  => 'yes',
	OM_ONLY => 'only',
	OM_SOME => 'some'
};

use constant BLOCK_COUNTRIES => qw/
	India
	Pakistan
	Indonesia
	Indanesia
	China
	Taiwan
	Afganistan
	Iran
	Brasil
	Columbia
	Venezuela
	Mexica
	Philippines
	Azerbajan
/;

my @block_countries = map { tr/_/ /; $_ } BLOCK_COUNTRIES;

# Query parameters
# default for 'Telecommute' => 'yes'
our ($kwrds, $locs, $offst) = ('', '', OM_YES);

# Precompiled queries
my $job_id_re     = qr|rl\.org/job/(\d+)|;
my $title_re      = qr|<h1>(.+?)</h1>|;
my $job_fields_re = qr|<a name="(\w+)"></a>.+? valign=top>\s+(.+?)\s+</td>|ms;


sub query($$$)
{	
	my ($kw, $lc, $ost) = @_;

	# get jobs list
	my $content = get( PERL_JOBS_URL . "/search?q=$kw&location=$lc&offsite=$ost" )
		or die "Can't get job search results";

	my @r = ($content =~ m|$job_id_re|g);
	\@r;
}

sub getjob($)
{
	use utf8;

	my $j = shift;
	my @acc;

	my $job_desc_html = get( PERL_JOBS_URL  . "/job/$j")
		or die "Internal error: failed to get job description!\n";

	utf8::decode($job_desc_html);

	if ($job_desc_html =~ m|$title_re|msi) { #dbg# say "Title: $0" and
		 push @acc, 'title', $1; }

	#::dbg( $job_desc_html);

	my @a = ($job_desc_html =~ m|$job_fields_re|g);
	push @acc, @a;

	\@acc;
}

sub print_job_desc(\%) 
{
	my $job_ref = shift;

	say STDERR "** Job " . '*' x 6;
	for my $k (keys %$job_ref) {
		say STDERR " |- $k => $job_ref->{$k}";
	}

	say STDERR "\n";
}

sub filter(\%)
{
	my $job = shift;

	return 0 if (not defined $job->{contact});

	for (@block_countries) {
		return 0 if (exists $job->{country} and $job->{country} =~ /$_/i);
	}

	# Update to do find 'local desirable' in more smart manner
	return 0 if ($job->{description} =~ /local/);

	return 1;
}

sub get_job_records($)
{
	my $rows = shift;
	my @jobs;

	#state $num = 0;
	for my $rc (@$rows) {
		my %j = @{ getjob($rc) };
		
		if (::IS_DBG_MODE) {
			print_job_desc %j;
			#exit 1;
		}


		next if not filter(%j);
		push @jobs, \%j;

		#last if $num++ == 5;
	}

	\@jobs;
}

sub request_jobs()
{
	get_job_records( query( $kwrds, $locs, $offst) );
}

package JobsPostMan;
use MIME::Lite;

sub send_letter(\%$)
{
	my ($j,$m) = (shift, shift);

	say $m;

	my $msg = MIME::Lite->new(
		#From    => 'journeyman@benderlogov.net',
		From    => 'jobber1310@mail.ru',
		To      => 'akaagun@ymail.com',
		Subject => '[looking for a job] ' . $j->{title},
		Data    => $j->{contact} . "\n\n" . $m
	);

	return 0;

	# Sending auth info on command line is generally a bad idea but for this script it is ok
	$msg->send('smtp', 'smtp.mail.ru', AuthUser => $ARGV[0], AuthPass => $ARGV[1] ) or
		die "Failed to send mail, stopped";

	1;
}

package JobsStore;
use DBIx::Simple;
use YAML::Tiny;
use Data::Dumper;

use constant {
	DBPATH => 'jobs',
	DBNAME => 'jpl_offers.db'
};


state $config = ''; 
{
	local $/ = 0, $config = <::DATA>;
}

# Loading configuration
my $yml = YAML::Tiny::Load($config) or die "Failed to parse config, stopped";
say $yml->{msg};
$yml->{msg} =~ s/\n/\n\n/g;
say $yml->{msg} and exit 0;

sub connect($$)
{
	my ($self, $path, $dbname) = @_;

	# TODO: rewrite as 'state' variable?
	my $db =  DBIx::Simple->new("dbi:SQLite:dbname=$path/$dbname", "", "", 
		{
			RaiseError => 1,
			AutoCommit => 0,
			# sqlite_allow_multiple_statements => 1
		} ) or die DBIx::Simple->error;

	if (not $db->{pragmas_set}) {
		$db->query("PRAGMA foreign_keys = ON");
		$db->{pragmas_set} = 1;
	}

	return $db;
}

sub create_schema($$) 
{
	my ($path, $name) = @_;

	die "Error in schema defenition!" if (not defined $yml->{schema});

	mkdir $path if (! -d $path);

	# pwd and user name are not used
	my $db = __PACKAGE__->connect($path, $name);

	for (@{$yml->{schema}}) {
		#say "Query: [$_]";
		$db->query($_) or die "Failed to create database: $db->error;\n query => $_\n";
	}

	$db->commit;
	$db->disconnect;
}
	
	
sub parse_fields(\%) 
{
	my $j = shift;
	
	::dbg { say "CONTACT_SRC: [$j->{contact}]"; };

	$j->{website} =~ s|^[^>]+>([A-Za-z0-9\.]+)</a>|$1|   if defined $j->{website};

	# Contact need more work as some smart person public it in weird formats
	#if ($j->{contact} !~ s|.*?([[:alpha:]][-+\w]+\@[\w.]+?\w+\.[[:alpha:]]{2,6}?)[\s.'"].*$|$1|ms) {
	#if ($j->{contact} !~ s|.*?\"?(^[[:alpha:]][\w.+-]*\@[\w.]+?\.[[:alpha:]]+).*|$1|ms) {
	if ($j->{contact} !~ s|.*?([\w.+-]+\@[\w]+\.[[:alpha:]]{2,8}).*|$1|ms) {
		# store old value for investigation
		$j->{raw_contact} = $j->{contact};
		say "Faulty Contact: $j->{contact}";

		# Apply various filters to correct smart? mail address representation
                # 1. : jobs (at) journatic (dot) com<br>
		if ($j->{contact} !~ s|.*?(\w+ \s* \(at\) \s* \w+ \s* \(dot\) \s* \w+).*|$1|sx) {
			undef $j->{contact};
		} else {
			my %rep = ('(dot)' => '.', '(at)' => '@',  ' ' => '');
			$j->{contact} =~ s/(\(dot\)|\(at\)|\s)/$rep{$1}/gs;
		}
	}


	::dbg { say 'CONTACT_DST: [' . ($j->{contact} ? $j->{contact} : '-') . ']' };
}

sub store_job(\%)
{
	my $j = shift;
	my $id = -1;

	my $db = __PACKAGE__->connect(DBPATH, DBNAME);

	my $firm_query = $db->query('select id from firm where company_name like ?', $j->{company_name})
		or die "Failed to store job description";

	my @ra = $firm_query->flat;
	if (@ra == 1) {
		($id) = @ra;
		goto SAVE_OFFER;
	}

	die "Logical database error: must be on firm record" if (@ra > 1);

	# All clear: should store firm information
	$db->query('insert into firm values(??)',
		undef,
		$j->{company_name },
		$j->{country      }, 
		$j->{location     },
		$j->{website      } ) or die "Failed to store firm information";

	($id) = $db->query('select last_insert_rowid()')->list or die "Can't get last inser rowid, stopped";

SAVE_OFFER:
	# say "Last id = $id";
	# Check if offer already exist?
	my $offers_res = $db->query('select title, posted_on, applyed from offer where ' .
			'firm_id    = ? and '   .
	            	'posted_on  = ? and '   .
			'title      = ?',
			$id,
			$j->{posted_on},
			$j->{title    } ) or die "Can't fetch offers record, stopped";

	my @offers = $offers_res->hashes;

	die "Abnormal offers quantity, stopped" if (@offers > 1);
	if (@offers == 1) {
		$j->{should_apply} = !$offers[0]->{applyed};
		goto OUT;
	}

	# No offer record written yet, store it
	$db->query('insert into offer values(??)',
		undef,
		$id, 
		$j->{jpl_id          },
		$j->{title           }, 
		$j->{contact         },
		$j->{raw_contact     },
		$j->{description     },
		$j->{skills_required }, 
		$j->{posted_on       },
		0, '' ) or die "Failed to store offer onfo, stopped";

	$db->query('select last_insert_rowid()')->into( $j->{offer_id} ) or die "Failed to fetch offer rowid, stopped";
	$j->{firm_id}      = $id;
	$j->{should_apply} = 1;
OUT:
	$db->commit;
	$db->disconnect;
}

sub make_send_list($)
{
	my $jobs = shift;
	my @apply_list;

	for (@$jobs) {
		# Note: Parse website and contat info
		parse_fields %$_;
		store_job %$_;
		push @apply_list, $_ if $_->{should_apply};
	}

	\@apply_list;
}

sub mark_applyed(\%)
{
	my $j = shift;

	my $db = __PACKAGE__->connect(DBPATH, DBNAME);

	$db->query(q|update offer set applyed = 'true' and apply_date = date() where id = ?|, $j->{offer_id} ) or
		die "Failed to update applyed offer entry, stopped";

	$db->disconnect;
}

sub apply($)
{
	my $jarr = shift;

	die "Message body not defined in config, stopped" if (! $yml->{msg});

	for my $j (@$jarr) {
		
		::dbg {
			say "Applying to $j->{company_name} as $j->{title}, contact: $j->{contact}";
		};

		mark_applyed(%$j) if JobsPostMan::send_letter(%$j, $yml->{msg});
	}
}

package main;

sub main()
{
	# dbg { say "Lets start!" };

	JobsStore::create_schema(JobsStore::DBPATH, JobsStore::DBNAME);
        JobsStore::apply( JobsStore::make_send_list( JPL::request_jobs() ) );
}


main();


__DATA__
---
schema:
 - >
   create table if not exists firm (
     id           integer primary key,
     company_name char(64) unique,
     country      char(128),
     location     char(128),
     website      char(64)
   );
 - >
   create table if not exists offer (
     id              integer primary key,
     firm_id         integer references firm(id) on delete cascade,
     jpl_id          integer,
     title           char(128),
     contact         char(128),
     raw_contact     text,
     description     text,
     skills_required text,
     posted_on       char(32),
     applyed         bool default false,
     apply_date      integer default null,
     unique (firm_id,title,posted_on)
   );
msg: |

	Greetings Human Beings!

	I'm tinny-silly robot which is on 'seems to never-end' quest of seeking nice (may be even telecommute) work for one very modest person I don't know very well, but which seems a nice Creature for my tiny mind opinion.

	He has significant skills in C/C++, some knowledge of distributed computing and interest in machine learning and neural networks design. But now he is seeking grail of wisdom at the Perl domain and I hope you'll help him in his mission. If you are willing to find out more, look at his profile: 

		http://linkedin.com/in/akarev
	
	Resume (+some certificates and recommendations) in PDF:

		http://www.box.com/shared/96d65cc39f086f10e6f2
	
	My body internals were published at:

		
	
	They are fleshed upon Perl, so you can think of it as 'code sample', but don't stare at me for too long, I don't like it! And note that my creator just starts to gain enlightenment at Perl wisdom.
	
	As I mentioned my protege has very modest abilities so I'll offer him for you at modest rate starting at: $23/hour, but trade is acceptable. Feel free to ignore this message, but note that you may loose something in your life that your concurrents can acquire.
	
	Good luck in your struggle against complicity, beloved Humans.
