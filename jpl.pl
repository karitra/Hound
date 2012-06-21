#!/usr/bin/env perl
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

use constant SCRIPT_VERSION => v0.3;

map {binmode $_, ':utf8' }  (*STDOUT, *STDERR);

use feature qw/
	say
	state
/;

use constant IS_DBG_MODE => 0;
use constant CRED_FILE   => '.dont.copy/cred';

BEGIN {
  # Needed by Postman module
  $ENV{CRED_FILE} = CRED_FILE;
}

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
	Afghanistan
	Aphganistan
	Afganistan
	Iran
	Brasilia
	Brasil
	Columbia
	Venezuela
	Mexica
	Philippines
	Azerbaijan
	Azerbajan
/;

my @block_countries = map {my $a = $_; $a =~ tr/_/ /; $a } BLOCK_COUNTRIES;

use constant STRANGE_DESC => qw/
   specifics_of_the_logic
/;

my @strange_desc = map {local $a = $_;  $a =~ tr/_/ /; $a } STRANGE_DESC;

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

	for (@strange_desc) {
		return 0 if ($job->{description} =~ /$_/i);
	}

	# Update to do find 'local desirable' in more smart manner
	return 0 if ($job->{description} =~ /local|LOCAL/);

	return 1;
}

sub get_job_records($)
{
	my $rows = shift;
	my @jobs;

	say "Requesting jobs list...";

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
use lib qw/scripts util/;
use TinyUtil;
Mailman->import; # never do this at home!
use Postman;
use Poster;

sub send_letter($\%$)
{
  my ($use_cgi, $j, $msg) = @_;

  say "Can't understand contact information from [$j->{raw_contact}]" unless ($j->{contact});

  return 0 unless $j->{contact};

  if ($use_cgi) {
	# say "CGI";
	return Poster::post_cgi( Gate::prepare_key(), 'jobber1310@mail.ru', '[need this job]' . $j->{contact}, $msg );
  } else {
	# say "Mail";
	# Deployment route
	 return Postman::send( undef, $j->{contact}, '[want to work with you] ' . $j->{title} , $msg);

	# Debug route
	# return Postman::send( undef, 'jobber1310@mail.ru', '[want to work with you] ' . $j->{contact} . ' ' .  $j->{title} , $msg);
  }
}


package JobsStore;

use DBIx::Simple;
use YAML::Tiny;
use Data::Dumper;

use Exporter 'import';
our @EXPORT = qw/
				  connect
				  create_schema
				  apply
				  make_send_list
/;

use constant {
	DBPATH => 'jobs',
	DBNAME => 'jpl_offers.db'
};


state $config = '';
{
	local $/;
	$config = <main::DATA>;
}

# Loading configuration
our $yml;
# say $yml->{msg};

sub prepare_yml()
{
  # 1. Load config first
  my $y         =  YAML::Tiny::Load($config) or die "Failed to parse config, stopped";
  $y->{msg_jpl} =~ s/\n/\n\n/g;

  do $ENV{CRED_FILE} or die 'Failed to read post user parameters, stopped';

  $y->{msg_jpl} =~ s/\$(\w+)\$/$Cfg::wrk_embedded_links{$1}/g;

  $y;
}


sub connect($$)
{
	my (undef, $path, $dbname) = @_;

	# TODO: rewrite as 'state' variable?
	my $db =  DBIx::Simple->new("dbi:SQLite:dbname=$path/$dbname", "", "", 
		{
			RaiseError => 1,
			AutoCommit => 0,
			# sqlite_allow_multiple_statements => 1
		} ) or die DBIx::Simple->error;

	unless ($db->{pragmas_set}) {
		$db->query("PRAGMA foreign_keys = ON");
		$db->{pragmas_set} = 1;
	}

	return $db;
}

sub create_schema($$)
{
	my ($path, $name) = @_;

	say "(Re)creating schema...";

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
		# say "Faulty Contact: $j->{contact}";

		# Apply various filters to correct smart? mail address representation
                # 1. : jobs (at) journatic (dot) com<br>
		if ($j->{contact} !~ s|.*?(\w+ \s* \(at\) \s* \w+ \s* \(dot\) \s* \w+).*|$1|sx) {
			#undef $j->{contact};

		  if ($j->{contact} =~ s|.*?(\w+ \s* AT \s* \w+ \s* DOT \s* \w+).*|$1|isx) {
			# say "contact: $j->{contact}";
			my %rep = (dot => '.', DOT => '.', at => '@',  AT => '@',' ' => '');

			if ($j->{contact} !~ s/(dot|DOT|at|AT|\s)/$rep{$1}/gs) {
			  undef $j->{contact};
			}

		  } else {
			undef $j->{contact};
		  }

		} else {
			my %rep = ('(dot)' => '.', '(at)' => '@',  ' ' => '');
			$j->{contact} =~ s/(\(dot\)|\(at\)|\s)/$rep{$1}/igs;
		}
	}

	$j->{company_name} = $j->{contact} unless ( $j->{company_name});

	::dbg { say "company: $j->{company_name}"; say 'CONTACT_DST: [' . ($j->{contact} ? $j->{contact} : '-') . ']' };
}

sub store_job(\%)
{
	my $j = shift;

	my $id            = -1;
	my $should_ignore =  0;

	my $db = __PACKAGE__->connect(DBPATH, DBNAME);

	# Note: may be memory consuming, but should be ok for this application
	my $r = $db->query('select id, ignore from firm where company_name like ?', $j->{company_name})
		or die "Failed to store job description";

	my @ra = $r->hashes;

	if (@ra == 1) {
	  $id            = $ra[0]->{id};
	  $should_ignore = $ra[0]->{ignore};
	  goto SAVE_OFFER;
	}

	die "Logical database error: must be on firm record" if (@ra > 1);

	# All clear: should store firm information
	$db->query('insert into firm(company_name, country, location, website) values(??)',
			   $j->{company_name },
			   $j->{country      },
			   $j->{location     },
			   $j->{website      } ) or die "Failed to store firm information";

	($id) = $db->query('select last_insert_rowid()')->list or die "Can't get last insert rowid, stopped";

SAVE_OFFER:
	#say "Last firm_id = $id, posted_on => $j->{posted_on}, title => $j->{title}";

	# Check if offer already exist?
	my $offers_res = $db->query( 'select title, posted_on, applied, id from offer where ' .
								 'firm_id    = ? and '   .
								 'posted_on  = ? and '   .
								 'title      = ?',
								 $id,
								 $j->{posted_on},
								 $j->{title    } ) or die "Can't fetch offers record, stopped";

	my @offers = $offers_res->hashes;

	die "Abnormal offers quantity, stopped" if (@offers > 1);
	if (@offers == 1) {
     	# say "Title: $offers[0]->{title}, applied: $offers[0]->{applied}";
		$j->{offer_id    } =  $offers[0]->{id};
		$j->{should_apply} = !$offers[0]->{applied};
		goto OUT;
	}

	# No offer record written yet, store it
	$db->query('insert into offer(' .
			   'firm_id, '.
			   'jpl_id, '.
			   'title, '.
			   'contact, '.
			   'raw_contact, '.
			   'description, '.
			   'skills_required,'.
			   'posted_on) values(??)',
		$id,
		$j->{internal_reference},
		$j->{title           },
		$j->{contact         },
		$j->{raw_contact     },
		$j->{description     },
		$j->{skills_required },
		$j->{posted_on       } ) or die "Failed to store offer onfo, stopped";

	$db->query('select last_insert_rowid()')->into( $j->{offer_id} ) or die "Failed to fetch offer rowid, stopped";
	# say "Get offer id => $j->{offer_id}";

	$j->{firm_id}      = $id;
	$j->{should_apply} = 1;
OUT:

	$j->{should_apply} = ($should_ignore eq 'false' or $should_ignore == 0) ? $j->{should_apply} : 0;

	# say "Apply for [$j->{title}]? Should apply: $j->{should_apply}, should ignore: $should_ignore";

	$db->commit;
	$db->disconnect;
}

sub make_send_list($)
{
	my $jobs = shift;
	my @apply_list;

	say q/Preparing 'apply' list.../;

	for (@$jobs) {
		# Note: Parse website and contat info
		parse_fields %$_;
		store_job %$_;
		push @apply_list, $_ if $_->{should_apply};
	}

	\@apply_list;
}

sub mark_applied(\%)
{
	my $j = shift;

	my $db = __PACKAGE__->connect(DBPATH, DBNAME);

	# say "Updating id => $j->{offer_id}";
	$db->query(q|update offer set applied = 1, apply_date = date() where id = ?|, $j->{offer_id} ) or
		die "Failed to update applied offer entry, stopped";

	$db->commit;
	$db->disconnect;
}

sub apply($)
{
	my $jarr = shift;

	say 'Applying for ', scalar @$jarr, ' offers';

	die "Message body not defined in config, stopped" unless $yml->{msg_jpl};

	for my $j (@$jarr) {

		::dbg {
			say "Applying to $j->{company_name}";
			say "  as       $j->{title}";
			say "  contact  $j->{contact}";
		};

		mark_applied(%$j) if JobsPostMan::send_letter(0, %$j, $yml->{msg_jpl} . "\n[id: $j->{firm_id}.$j->{offer_id}]" );
	}
}

package main;

sub main()
{
  # dbg { say "Lets start!" };

  # 1. Prepare YAML config
  $yml = JobsStore->prepare_yml;

  # 2. Do the job ;)
  JobsStore::create_schema(JobsStore::DBPATH, JobsStore::DBNAME);
  JobsStore::apply( JobsStore::make_send_list( JPL::request_jobs() ) );
}


main();

__DATA__
---
schema:
 - >
   create table if not exists firm (
     id              integer primary key,
     company_name    char(64) unique,
     country         char(128),
     location        char(128),
     website         char(64),
     ignore          bool default false,
     num_of_declines integer default 0
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
     applied         bool default false,
     apply_date      integer default null,
     response        bool default false,
     unique (firm_id,title,posted_on)
   );
msg_jpl: |
  Greetings Human Beings!
  I'm tinny-silly robot which is on 'seems to never-end' quest of seeking nice (may be even telecommute and for long term) work for one very modest person I don't know very well, but which seems a nice critter for my tiny mind opinion.
  He has significant skills in C/C++, some knowledge of distributed computing and interest in machine learning and neural networks design. But now he is seeking grail of wisdom at the Perl domain and I hope you'll help him in his mission. If you are willing to find out more, look at his profile:
      $linked_profile$
  Resume (+some certificates and recommendations) in PDF:
      $resume_download$
  My body internals were published at:
      $github$
  They are fleshed upon Perl, so you can think of it as 'code sample', but don't stare at me for too long, I don't like it! And note that my creator just starts to gain enlightenment at Perl wisdom.
  As I mentioned, my protege has very modest abilities so I'll offer him for you at a modest rate starting at: $22.59/hour (can be discussed).
  Feel free to ignore this message, but note that you may loose something in your life that your concurrents can acquire.
  Good luck in your struggle against complicity, beloved Humans!
msg_jpl_ru: |
  Приветствую вас, Люди!
  Я робот. Маленький, глупенький робот. Меня создавали в минуты отчаянного безделья, длинными весенними вечерами в свободное от бадминтона и от сопровождения сайтов о грибах и Тамерлане время, для очень важной и, повидимому, невыполнимой миссии - найти работу (желательно удаленную) для одного очень хорошего, но очень скромного человеческого организма. Но сейчас речь не обо мне, а об упомянутом организме.
  У него есть значительный опыт работы с Си/Си++, некоторое знание о распределенных приложениях и мизерное увлечение тем, что именуется Machine Learning и Нейронные Сети. Сейчас он находится в поисках грааля мудрости в обители Адептов Perl (это я про perlmonks). Есть у него некоторое знание Явы, динамических и функциональных языков. Подробнее о нём можно узнать тут:
    $linked_profile$
  Инструкия от него (+несколько страниц гарантии) в PDF:
    $resume_download$
  С моей начинкой можно ознакоимться тут:
      $github$
  Я наращивал свой жирок с помощью Perl, так что мои 'внутренности' можно расценить как 'пример кода', но не нужно на меня таращиться слишком долго, это меня смущает. И учтите что субъект, создавший меня, только вступил на путь обретения просветления в Perl'овой мудрости.
  Как я упоминал, мой 'протеже' имеет очень скромные возможности, поэтому я могу предложить его вам за очень скромное вознограждение начиная от $20/час (но рейт можно обсудить).
  Вы можете проигнорировать это сообщение, но не забывайте, что вы можете пропустить что-то в своей деятельности, что ваши конкуренты могут приобрести.
  До скорых встреч, любимые мои Человеки!

