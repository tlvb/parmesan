# parmesan
perl fork-and-forget slightly evolved to work on a multi-host system

## What is this?
It's a slight extension of a fork-and-forget processing flow so that multiple hosts can be used for batch processing.
## Use case
Basically, if you have a list of files you need to do some batch processing on you might make
a script that iterates through that list and invokes the processing on each file.  
If you have a computer with multiple cores, and a single batch job does not use all of them,
you might write your script so that multiple batch jobs run in parallel.
Now, if you have multiple computers on the network, you might want to run multiple jobs
in parallel, on multiple hosts. This is where parmesan enters the arena.
## What does it do?
Given a hash of `host=>max-pids`, where max-pids being the host's cpu count or some other
metric that determines how many jobs you want to run at each host, and given a range or array to iterate over,
it iterates over the range (or array), and selects a host not running at max-pids (or waits for one to become free)

When a host has been selected, parmesan forks. The child process then calls your userdefined running sub (`run`)
with the host name, and the current value of the iterator, and the parent process increases the
number-of-jobs-running counter for that host. Once a job finishes on a host, that is the `run` function of a particular thread returns, the job counter for that host is decreased.
Apart from that, `mastersetup` is invoked once, before iterating, and `masterteardown` is invoked once, after.
Likewise, `setup` and `teardown` is invoked once per host before and after iteration.
## What does it not do?
Any network stuff, proper error checking. Caveat emptor.
Basically, you have to make sure files are in the right place(s) manually, e.g. by invoking a with appropriate
parameters `scp` or `rsync` and remove whatever should be removed with e.g. `ssh` + `rm`. You can do this either
in `setup`/`teardown` or as the first and last parts of `run` at your discretion.

You also have to run your actual job on the host in question manually in `run`, e.g.
```perl
`ssh $host do_the_thing_with $item`;
```

## Example:
```perl
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
	`ssh $host 'sleep 3; uname -a > /tmp/parmesan/parmesan_test.$host.$item'`;
	`scp $host:/tmp/parmesan/parmesan_test.$host.$item /tmp/parmesan_results`;
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
```
