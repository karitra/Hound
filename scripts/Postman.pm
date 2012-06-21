package Postman;

use strict;
use warnings;

use Email::Sender::Simple qw/sendmail/;
use Email::Simple;
use Email::Simple::Creator;
use Email::Sender::Transport::SMTP;

use Exporter 'import';
our @EXPORT = qw/send/;


use feature qw/say/;

sub transport();

our $smpts_trans = transport;

sub transport()
{
	do ($ENV{CRED_FILE}) or die "Failed to read post user parameters => $@, stopped";

	# die "uname: [$Cfg::post_cred{uname}], pass: [$Cfg::post_cred{pass}]";

	my $tr = Email::Sender::Transport::SMTP->new(
		host => 'benderlogov.net',
		port => 465,
		ssl  => 1,
		sasl_username => $Cfg::post_cred{uname},
		sasl_password => $Cfg::post_cred{pass } );

	$tr;
}

sub send($$$$)
{
	my ($from, $to, $sbj, $msg) = @_;

#	die "Sending from [$from] to [$to]";

	my $eml = Email::Simple->create(
		header => [
			To      => $to,
			From    => $from ? $from : 'journeyman@benderlogov.net',
			Subject => $sbj
		],
		body => $msg
	);

	my $eml_copy = Email::Simple->create(
		header => [
			To      => 'akaagun@ymail.com',
			From    => $from ? $from : 'journeyman@benderlogov.net',
			Subject => 'Copy: ' . $sbj
		],
		body => $msg
	);

    say "\tSending to $to...";

	# TODO: return 1 or 0 depending on error
	sendmail( $eml,      { transport => $smpts_trans } ) or die "Failed to send mail";
	sendmail( $eml_copy, { transport => $smpts_trans } ) or die "Failed to send copy of mail";
}

sub dummy_fetch()
{

}

# Postman::send(undef, 'jobber1310@mail.ru', '[want this job] Test1', "Msessage number 1\nline2\nSee you");

1;

