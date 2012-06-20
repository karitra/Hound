package Poster;
use Exporter qw/import/;
our @EXPORT = qw/post/;

use LWP::UserAgent;
use lib '../scripts';

use TinyGate qw/prepare_key/;

use feature qw/say/;

use constant URL => 'https://secure41.nocdirect.com/~jbenderl/cgi-bin/jposter.cgi';
use constant DEFAULT_KEY => 'Ilikethis_job1310';

sub post_cgi($$$$) {
  my ($k,$to,$sbj,$msg) = @_;

  my $ua = new LWP::UserAgent(agent => 'Mozilla/5.0');
  # $ua->add_handler('request_send', sub {shift->dump; return} );

  my $r  = $ua->post( URL, Content =>
					  { ks => $k, to => $to, sbj => $sbj, msg => $msg} ) or die 'Failed to send request, stopped';

  say 'Error: '. $r->status_line unless ($r->is_success);

  # say $r->decoded_content;
  return $r->is_success ? 1 : 0;
}

sub sendmail($$$$)
{
	...
}

#post_cgi( prepare_key(DEFAULT_KEY), 'akaagun@ymail.com',
#	  '[need your job] jb Some test', "Hello world\n\nDurty world!\n") or die "Failed to post";



