#!/bin/env perl
#

use strict;
use warnings;

package TinyGate;

use Exporter qw/import/;
our @EXPORT    = qw/auth/;
our @EXPORT_OK = qw/prepare_key from_file_key/;

use Digest::MD5 qw/md5_hex/;
use File::HomeDir;

use constant SALTY_DIR => '/scripts/cred';

sub get_salt()
{
  my @gmt = gmtime;
  sprintf('%02x%02x%02x%02x', $gmt[2], $gmt[3], $gmt[4], $gmt[6] );
}

sub prepare_key($)
{
  my $k = shift;
  my $s = get_salt;

  return  md5_hex($k . $s);
}

sub from_file_key() {
  my @gmt = gmtime;
  my $s   = get_salt;

  local $/;

  open KH, ('<' . File::HomeDir->my_home . SALTY_DIR . '/salty.one') or die "Fail to eat with salt, stopped";
  my $lk = <KH>;
  close KH;

  $lk =~ s/\n//g;

  return  md5_hex($lk . $s);
}

sub auth($)
{
  return (from_file_key eq shift) ? 1 : 0;
}

1;
