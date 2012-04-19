use strict;
use warnings;
use Test::More;

plan skip_all => "hangs currently";

use AnyEvent;
use Log::Stash::Input::Freeswitch;
use Log::Stash::Output::Test;

my $cv = AnyEvent->condvar;
my $output = Log::Stash::Output::Test->new(
    cb => sub { $cv->send },
);
my $input = Log::Stash::Input::Freeswitch->new(
    host => "localhost",
    secret => "FxRU%-gW?g9RxNJ{);qt",
    output_to => $output,
);
ok $input;

my $t = AnyEvent->timer(after => 3000, cb => sub { $cv->croak("Timed out waitinf for events") });

$cv->recv;
undef $t;

ok $output->message_count >= 1;

done_testing;

