package Parmesan;
use warnings;
use strict;
use strictures 2;

#{{{

=pod

What is this?
It's a slight extension of a fork-and-forget processing flow so that multiple hosts can be used

What does it do?
Given a hash of host=>max-pids, where max-processes may be the host's cpu count or something
like that, and given a range or array to iterate over, it iterates over the range (or array),
selecting a host not running at max-pids (or waits for one to become free), forks, and calls
your userdefined running sub with the host name, and the current value of the iterator.

What does it not do?
Any network stuff, proper error checking. Caveat emptor.

Example:

use warnings;
use strict;
use strictures 2;
use Parmesan;

my %hosts = (
	foo=>4,
	bar=>2,
	baz=>1,
	barbazar=>1,
	xyzzy=>2
);

sub mastersetup {
	print STDERR "mastersetup\n";
	`mkdir /tmp/parmesan_results`;
}

sub setup {
	my $host = shift;
	print STDERR "setup ($host)\n";
	`ssh $host mkdir /tmp/parmesan`
}

sub run {
	my ($host, $item) = @_;
	print STDERR "run ($host, $item)\n";
	`ssh $host 'uname -a > /tmp/parmesan/parmesan_test.$host.$item'`;
	`scp $host:/tmp/parmesan/parmesan_test.$host.$item /tmp/parmesan_results`;
	sleep 1;
}

sub teardown {
	my $host = shift;
	print STDERR "teardown ($host)\n";
	`ssh $host rm -rf /tmp/parmesan`
}

sub masterteardown {
	print STDERR "masterteardown\n";
	`cd /tmp ; tar czf parmesan_results.tar.gz parmesan_results`;
	`rm -rf /tmp/parmesan_results`
}

my $p = Parmesan->new(
	hosts=>\%hosts,
	range=>[0,127],
	mastersetup=>\&mastersetup,
	setup=>\&setup,
	run=>\&run,
	teardown=>\&teardown,
	masterteardown=>\&masterteardown
);

$p->run();

=cut

# }}}

sub new {
	my $class = shift;
	my %opts = @_;
	my $self = {
		hosts=>$opts{hosts}                   // {},
		mastersetup=>$opts{mastersetup}       // sub { print STDERR "INFO: no mastersetup function defined\n";        },
		setup=>$opts{setup}                   // sub { print STDERR "INFO: no setup function defined [$_[0]]\n";      },
		run=>$opts{run}                       // sub { print STDERR "WARN: no run function defined [$_[0], $_[1]]\n"; },
		teardown=>$opts{teardown}             // sub { print STDERR "INFO: no teardown function defined [$_[0]]\n";   },
		masterteardown=>$opts{masterteardown} // sub { print STDERR "INFO: no masterteardown function defined\n";     },
		running=>{}
	};
	$self->{array} = $opts{array} if exists $opts{array};
	$self->{range} = $opts{range} if exists $opts{range};

	bless $self, $class;
	return $self;
}

sub runitem {
	my ($self, $item) = @_;
	my $host = '';
	print "available: "; print " $_:$self->{hosts}->{$_}" for keys %{$self->{hosts}}; print "\n";
	for my $h (keys %{$self->{hosts}}) {
		next if $self->{hosts}->{$h} == 0;
		$host = $h;
	}
	if ($host eq '') {
		my $pid = wait;
		until (exists $self->{running}->{$pid}) {
			$pid = wait;
		}
		my $host = delete $self->{running}->{$pid};
		$self->{hosts}->{$host} += 1;
	}
	if ($host ne '') {
		my $pid = fork();
		if ($pid == 0) { # we are the child
			$self->{run}->($host, $item);
			exit 0;
		}
		elsif ($pid > 0) { # we are the parent
			$self->{hosts}->{$host} -= 1;
			$self->{running}->{$pid} = $host;
		}
		else { # we are in error
			die "fork() returned < 0\n$!";
		}
	}
}

sub run {
	my $self = shift;
	$self->{mastersetup}->();
	$self->{setup}->($_) for keys %{$self->{hosts}};
	if (exists $self->{array}) {
		for my $item (@{$self->{array}}) {
			$self->runitem($item);
		}
	}
	elsif (exists $self->{range}) {
		for my $item ($self->{range}->[0]..$self->{range}->[1]) {
			$self->runitem($item);
		}
	}
	else {
		print STDERR "WARN: neither a array nor a range to iterate over is defined\n";
	}
	while (1) {
		my $pid = wait;
		until ($pid < 0 or exists $self->{running}->{$pid}) {
			$pid = wait;
		}
		delete $self->{running}->{$pid};
		last if (0 == keys %{$self->{running}})
	}
	$self->{teardown}->($_) for keys %{$self->{hosts}};
	$self->{masterteardown}->();
}

1;
