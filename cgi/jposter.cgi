#!/usr/bin/perl
#

use strict;
use warnings;

use File::HomeDir;
use CGI qw/:standard https/;
use CGI::Carp qw/fatalsToBrowser/;

use constant DEBUG_MODE => 0;
use constant MM_SCRIPTS => (DEBUG_MODE) ? '../scripts' : File::HomeDir->my_home . '/scripts';

$CGI::POST_MAX=1024 * 100;

BEGIN {
  unshift @INC,  MM_SCRIPTS;
}

use TinyUtil;
use TinyGate;
MailMan->import;

my $why = q/Don't know why!/;

unless (https) {
  $why = 'Wrong way?';
  goto SOMETHING_WRONG;
}

if (param) {
  my ($to ) = param('to' );
  my ($msg) = param('msg');
  my ($ks ) = param('ks' );
  my ($sbj) = param('sbj');

  goto SOMETHING_WRONG unless ( $to and $msg and $ks and $sbj);

  if (auth $ks ) {
	if (Mailman::send(undef, $to, $sbj, $msg)) {
	  out header,
		start_html("Because you're lucky"),
		h1('Job done'), hr,
		end_html;
	  exit 0;
	} else {
	  $why = "Failed to send...";
	  goto SOMETHING_WRONG;
	}
  } else {
	  $why = "Failed get in...";
	  goto SOMETHING_WRONG;
  }

} else {
SOMETHING_WRONG:

  out
	header,
	start_html($why),
	h1(q/I think you've missed something!/), hr,
	end_html;
  exit 1;
}
