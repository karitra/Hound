#!/bin/env perl
#

use strict;
use warnings;

package TinyUtil;
use Exporter 'import';
our @EXPORT = qw/out/;

sub out { print @_ }

package Mailman;
use MIME::Lite;

use Exporter 'import';
our @EXPORT = qw/send/;

use constant DEFAULT_SENDER => 'journeyman@benderlogov.net';

sub send($$$$)
{
  my ($from, $to, $sbj, $msg) = @_;

  my $m = MIME::Lite->new(
	  From    => $from ? $from : DEFAULT_SENDER,
	  To      => $to,
	  Subject => $sbj ? $sbj : '[no subject]',
	  Type    => 'text/plain',
	  Data    => $msg
  );

  $m->send;
}

1
