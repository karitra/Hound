#!/usr/bin/env perl
#

use CGI qw/:standard/;

# Don't do this at home as it is very inefficient!
do $ENV{MM_SCRIPTS} . '/util.pl';
do $ENV{MM_SCRIPTS} . '/auth.pl';


if (param) {
  my ($to ) = param('to' );
  my ($msg) = param('msg');
  my ($key) = param('ks');

  goto SOMETHING_WRONG until ( $to or $msg or $key );

  if (Gate::auth $key ) { out "Failed to send" until Mailman::send($from, $to, $msg); }

} else {
SOMETHING_WRONG:
  out
	header,
	start_html,
	h1(q/I think you've missed something!/), hr,
	end_html;

  exit 1;
}
