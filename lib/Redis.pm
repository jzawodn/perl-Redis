package Redis;

use warnings;
use strict;

use IO::Socket::INET;
use Data::Dumper;
use Carp qw/confess/;
use Encode;

=head1 NAME

Redis - perl binding for Redis database

=cut

our $VERSION = '1.2001';


=head1 DESCRIPTION

Pure perl bindings for L<http://code.google.com/p/redis/>

This version supports protocol 1.2 or later of Redis available at

L<git://github.com/antirez/redis>

This documentation
lists commands which are exercised in test suite, but
additinal commands will work correctly since protocol
specifies enough information to support almost all commands
with same peace of code with a little help of C<AUTOLOAD>.

=head1 FUNCTIONS

=head2 new

  my $r = Redis->new; # $ENV{REDIS_SERVER} or 127.0.0.1:6379

  my $r = Redis->new( server => '192.168.0.1:6379', debug = 0 );

=cut

sub new {
	my $class = shift;
	my $self = {@_};
	$self->{debug} ||= $ENV{REDIS_DEBUG};

	$self->{sock} = IO::Socket::INET->new(
		PeerAddr => $self->{server} || $ENV{REDIS_SERVER} || '127.0.0.1:6379',
		Proto => 'tcp',
	) || die $!;

	bless($self, $class);
	$self;
}

# we don't want DESTROY to fallback into AUTOLOAD
sub DESTROY {}

our $AUTOLOAD;
sub AUTOLOAD {
	my $self = shift;

	use bytes;

	my $sock = $self->{sock} || die "no server connected";

	my $command = $AUTOLOAD;
	$command =~ s/.*://;

	warn "## $command ",Dumper(@_) if $self->{debug};

	unshift @_, uc($command);

	my $send
 			= "*".(scalar @_)
			. "\r\n"
 			. join("", map { "\$". length($_) ."\r\n". $_ ."\r\n" } @_)
			;

	warn ">> $send" if $self->{debug};
	print $sock $send;

	if ( $command eq 'quit' ) {
		close( $sock ) || die "can't close socket: $!";
		return 1;
	}

	my $result = <$sock> || die "can't read socket: $!";
#Encode::_utf8_on($result);
	warn "<< $result" if $self->{debug};
	my $type = substr($result,0,1);
	$result = substr($result,1,-2);

	if ( $command eq 'info' ) {
		my $hash;
		foreach my $l ( split(/\r\n/, $self->__read_bulk($result) ) ) {
			my ($n,$v) = split(/:/, $l, 2);
			$hash->{$n} = $v;
		}
		return $hash;
	}

	if ( $type eq '-' ) {
		confess "[$command] $result";
	} elsif ( $type eq '+' ) {
		return $result;
	} elsif ( $type eq '$' ) {
		return $self->__read_bulk($result);
	} elsif ( $type eq '*' ) {
		return $self->__read_multi_bulk($result);
	} elsif ( $type eq ':' ) {
		return $result; # FIXME check if int?
	} else {
		confess "unknown type: $type", $self->__read_line();
	}
}

sub __read_bulk {
	my ($self,$len) = @_;
	return undef if $len < 0;

	my $v;
	if ( $len > 0 ) {
		read($self->{sock}, $v, $len) || die $!;
#Encode::_utf8_on($v);
		warn "<< ",Dumper($v),$/ if $self->{debug};
	}
	my $crlf;
	read($self->{sock}, $crlf, 2); # skip cr/lf
	return $v;
}

sub __read_multi_bulk {
	my ($self,$size) = @_;
	return undef if $size < 0;
	my $sock = $self->{sock};

	$size--;

	my @list = ( 0 .. $size );
	foreach ( 0 .. $size ) {
		$list[ $_ ] = $self->__read_bulk( substr(<$sock>,1,-2) );
	}

	warn "## list = ", Dumper( @list ) if $self->{debug};
	return @list;
}

1;

__END__

=head1 Connection Handling

=head2 quit

  $r->quit;

=head2 ping

  $r->ping || die "no server?";

=head1 Commands operating on string values

=head2 set

  $r->set( foo => 'bar' );

  $r->setnx( foo => 42 );

=head2 get

  my $value = $r->get( 'foo' );

=head2 mget

  my @values = $r->mget( 'foo', 'bar', 'baz' );

=head2 incr

  $r->incr('counter');

  $r->incrby('tripplets', 3);

=head2 decr

  $r->decr('counter');

  $r->decrby('tripplets', 3);

=head2 exists

  $r->exists( 'key' ) && print "got key!";

=head2 del

  $r->del( 'key' ) || warn "key doesn't exist";

=head2 type

  $r->type( 'key' ); # = string

=head1 Commands operating on the key space

=head2 keys

  my @keys = $r->keys( '*glob_pattern*' );

=head2 randomkey

  my $key = $r->randomkey;

=head2 rename

  my $ok = $r->rename( 'old-key', 'new-key', $new );

=head2 dbsize

  my $nr_keys = $r->dbsize;

=head1 Commands operating on lists

See also L<Redis::List> for tie interface.

=head2 rpush

  $r->rpush( $key, $value );

=head2 lpush

  $r->lpush( $key, $value );

=head2 llen

  $r->llen( $key );

=head2 lrange

  my @list = $r->lrange( $key, $start, $end );

=head2 ltrim

  my $ok = $r->ltrim( $key, $start, $end );

=head2 lindex

  $r->lindex( $key, $index );

=head2 lset

  $r->lset( $key, $index, $value );

=head2 lrem

  my $modified_count = $r->lrem( $key, $count, $value );

=head2 lpop

  my $value = $r->lpop( $key );

=head2 rpop

  my $value = $r->rpop( $key );

=head1 Commands operating on sets

=head2 sadd

  $r->sadd( $key, $member );

=head2 srem

  $r->srem( $key, $member );

=head2 scard

  my $elements = $r->scard( $key );

=head2 sismember

  $r->sismember( $key, $member );

=head2 sinter

  $r->sinter( $key1, $key2, ... );

=head2 sinterstore

  my $ok = $r->sinterstore( $dstkey, $key1, $key2, ... );

=head1 Multiple databases handling commands

=head2 select

  $r->select( $dbindex ); # 0 for new clients

=head2 move

  $r->move( $key, $dbindex );

=head2 flushdb

  $r->flushdb;

=head2 flushall

  $r->flushall;

=head1 Sorting

=head2 sort

  $r->sort("key BY pattern LIMIT start end GET pattern ASC|DESC ALPHA');

=head1 Persistence control commands

=head2 save

  $r->save;

=head2 bgsave

  $r->bgsave;

=head2 lastsave

  $r->lastsave;

=head2 shutdown

  $r->shutdown;

=head1 Remote server control commands

=head2 info

  my $info_hash = $r->info;

=head1 AUTHOR

Dobrica Pavlinusic, C<< <dpavlin at rot13.org> >>

Jeremy Zawodny C<< <Jeremy at Zawodny.com> >> hacked this up for use at
Craigslist

=head1 BUGS

Please report any bugs or feature requests to C<bug-redis at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Redis>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Redis
	perldoc Redis::List
	perldoc Redis::Hash


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Redis>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Redis>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Redis>

=item * Search CPAN

L<http://search.cpan.org/dist/Redis>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009-2010 Dobrica Pavlinusic, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Redis
