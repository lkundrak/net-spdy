package Net::SPDY::Framer;

=head1 NAME

Net::SPDY::Framer - SPDY protocol implementation

=head1 ALPHA WARNING

B<Please read carefully:> This is an ALPHA stage software.
In particular this means that even though it probably won't kill your cat,
re-elect George W. Bush nor install Solaris 11 Express edition to your hard
drive, it is in active development, functionality is missing and no APIs are
stable.

See F<TODO> file in the distribution to learn about missing and planned
functionality. You are more than welcome to join the development and submit
patches with fixes or enhancements.  Bug reports are probably not very useful
at this point.

=head1 SYNOPSIS

  use Net::SPDY::Framer;

  my $framer = new Net::SPDY::Framer ({
      compressor => new Net::SPDY::Compressor,
      socket => $socket,
  });

  $framer->write_ping(data => 'chuj');
  while (my %frame = $framer->read_frame) {
    last if $frame{control} and $frame{type} eq Net::SPDY::Framer::PING;
  }

=head1 DESCRIPTION

B<Net::SPDY::Framer> provides SPDY protocol access on top of a network socket.
It serializes and deserializes packets as they are, without implementing any
other logic. For session management, see L<Net::SPDY::Session>.

=cut

use strict;
use warnings;

our $VERSION = '0.1';

=head1 CONSTANTS

For the actual values refer to the protocol specification.

=over 4

=item Frame types

C<SYN_STREAM>, C<SYN_REPLY>, C<RST_STREAM>, C<SETTINGS>, C<PING>, C<GOAWAY>,
C<HEADERS>, C<WINDOW_UPDATE>, C<CREDENTIAL>.

=cut

# Frame types
use constant {
	SYN_STREAM	=> 1,
	SYN_REPLY	=> 2,
	RST_STREAM	=> 3,
	SETTINGS	=> 4,
	PING		=> 6,
	GOAWAY		=> 7,
	HEADERS		=> 8,
	WINDOW_UPDATE	=> 9,
	CREDENTIAL	=> 10,
};

=item Flags

C<FLAG_FIN>, C<FLAG_UNIDIRECTIONAL>.

=back

=cut

# For SYN_STREAM, SYN_RESPONSE
use constant {
	FLAG_FIN	=> 0x01,
	FLAG_UNIDIRECTIONAL => 0x02,
};

=head1 PROPERTIES

=over 4

=item compressor

L<Net::SPDY::Compressor> object representing the Zlib streams (one in each
direction) used by the framer.

=item socket

L<IO::Handle> instance that is used for actual network communication.

=back

=head1 METHODS

=over 4

=item new { socket => SOCKET, compressor => COMPRESSOR }

Creates a new framer instance. You need to create and pass both the socket for
the network communication and the compressor instance.

=cut

sub new
{
	my $class = shift;
	my $self = bless shift, $class;

	return $self;
}

sub name_value
{
	my $self = shift;

	my $name_value = pack 'N', (scalar @_ / 2);
	while (my $name = shift) {
		my $value = shift;
		die 'No value' unless defined $value;
		$name_value .= pack 'N a* N a*',
			map { length $_ => $_ }
			(lc ($name) => $value);
	}
	return $name_value;
}

sub write_frame
{
	my $self = shift;
	my %frame = @_;

	$frame{length} = length $frame{data};

	$self->{socket}->write (pack 'N', ($frame{control} ? (
		$frame{control} << 31 |
		$frame{version} << 16 |
		$frame{type}
	) : (
		$frame{control} << 31 |
		$frame{stream_id}
	))) or die 'Short write';

	$self->{socket}->write (pack 'N', (
		$frame{flags} << 24 |
		$frame{length}
	)) or die 'Short write';

	$self->{socket}->write ($frame{data})
		or die 'Short write';
}

sub write_syn_stream
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N c c a*',
		($frame{stream_id} & 0x7fffffff),
		($frame{associated_stream_id} & 0x7fffffff),
		($frame{priority} & 0x07) << 5,
		($frame{slot} & 0xff),
		$self->{compressor}->compress ($self->name_value (@{$frame{header_block}}));

	$self->write_frame (
		control => 1,
		version => 3,
		type	=> 1,
		flags	=> $frame{flags} || 0,
		data	=> $frame{data},
	);
}

sub write_syn_reply
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N a*',
		($frame{stream_id} & 0x7fffffff),
		$self->{compressor}->compress ($self->name_value (@{$frame{header_block}}));

	$self->write_frame (
		control	=> 1,
		version	=> 3,
		type	=> 2,
		flags	=> $frame{flags} || 0,
		data	=> $frame{data},
	);
}

sub write_settings
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N', scalar @{$frame{nv}};
	foreach my $entry (@{$frame{nv}}) {
		$frame{data} .= pack 'N',
			($entry->{flags} & 0x000000ff) |
			(($entry->{id} << 24) & 0xffff0000) |
			(($entry->{id} << 16) & 0x0000ff00);
		$frame{data} .= pack 'N', $entry->{value};
	}

	$self->write_frame (
		control	=> 1,
		version	=> 3,
		type	=> 4,
		flags	=> $frame{flags} || 0,
		data	=> $frame{data},
	);
}

sub write_ping
{
	my $self = shift;
	my %frame = @_;

	die 'Ping payload has to be 4 characters'
		unless length $frame{data} == 4;
	$self->write_frame (
		control	=> 1, # 1 bit control=1, otherwise=0
		version	=> 3, # 15 bits
		type	=> 6, # 16 bits, ping=6
		flags	=> $frame{flags} || 0,
		data	=> $frame{data},
	);
}

sub write_goaway
{
	my $self = shift;
	my %frame = @_;

	$frame{data} = pack 'N N',
		($frame{last_good_stream_id} & 0x7fffffff),
		$frame{status};

	$self->write_frame (
		control	=> 1,
		version	=> 3,
		type	=> 7,
		flags	=> $frame{flags} || 0,
		data	=> $frame{data},
	);
}

sub read_nv
{
	my $self = shift;
	my $buf = shift;
	my @retval;

	my $entries;
	my $name_value = $self->{compressor}->uncompress ($buf);

	($entries, $name_value) = unpack 'N a*', $name_value;
	foreach (1..$entries) {
		my $len;
		my $name;
		my $value;

		($len, $name_value) = unpack 'N a*', $name_value;
		($name, $name_value) = unpack "a$len a*", $name_value;

		($len, $name_value) = unpack 'N a*', $name_value;
		($value, $name_value) = unpack "a$len a*", $name_value;

		push @retval, $name => $value;

	}

	return @retval;
}

sub read_syn_stream
{
	my $self = shift;
	my %frame = @_;
	my $buf;


	($frame{stream_id}, $frame{associated_stream_id},
		$frame{priority}, $frame{slot}, $frame{header_block}) =
		unpack 'N N c c a*', delete $frame{data};

	$frame{stream_id} &= 0x7fffffff;
	$frame{associated_stream_id} &= 0x7fffffff;
	$frame{priority} = ($frame{priority} & 0x07) << 5;
	$frame{slot} &= 0xff;
	$frame{header_block} = {$self->read_nv ($frame{header_block})};

	return %frame;
}

sub read_syn_reply
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	($frame{stream_id}, $frame{header_block}) =
		unpack 'N a*', delete $frame{data};
	$frame{header_block} = {$self->read_nv ($frame{header_block})};

	return %frame;
}

sub read_settings
{
	my $self = shift;
	my %frame = @_;
	my $buf;

	($frame{entries}, $frame{data}) =
		unpack 'N a*', $frame{data};
	$frame{nv} = [];

	foreach (1..$frame{entries}) {
		my %entry;
		my $head;
		($head, $entry{value}, $frame{data}) =
			unpack 'N N a*', $frame{data};
		$entry{id} = ($head & 0xffffff00) >> 8;
		$entry{id} = ($entry{id} >> 16 | $entry{id} << 16)
			& 0x00ffffff;
		$entry{flags} = ($head & 0x000000ff);
		push @{$frame{nv}}, \%entry;
	}
	delete $frame{data};

	return %frame;
}

sub read_ping
{
	my $self = shift;
	my %frame = @_;

	die 'Mis-sized ping frame'
		unless $frame{length} == 4;

	return %frame;
}

sub read_goaway
{
	my $self = shift;
	my %frame = @_;

	die 'Mis-sized goaway frame'
		unless $frame{length} == 8;
	my $last_good_stream_id;
	($last_good_stream_id, $frame{status}) = unpack 'N N', delete $frame{data};
	$frame{last_good_stream_id} = ($last_good_stream_id & 0x7fffffff);

	return %frame;
}

sub read_frame
{
	my $self = shift;
	my $buf;

	# First word of the frame header
	return () unless $self->{socket};
	my $ret = $self->{socket}->read ($buf, 4);
	die 'Read error '.$! unless defined $ret;
	return () if $ret == 0;
	die 'Short read' if $ret != 4;
	my $head = unpack 'N', $buf;
	my %frame = (control => ($head & 0x80000000) >> 31);

	if ($frame{control}) {
		$frame{version}	= ($head & 0x7fff0000) >> 16;
		$frame{type} = ($head & 0x0000ffff);
		die 'Bad version '.$frame{version} unless $frame{version} == 3;
	} else {
		$frame{stream_id} = ($head & 0x7fffffff);
	};

	# Common parts of the header
	$self->{socket}->read ($buf, 4) == 4 or die 'Read error';
	my $body = unpack 'N', $buf;
	$frame{flags} = ($body & 0xff000000) >> 24;
	$frame{length} = ($body & 0x00ffffff);

	# Frame payload
	unless ($frame{length}) {
		$frame{data} = '';
		return %frame;
	}
	$self->{socket}->read ($frame{data}, $frame{length})
		or die 'Read error';

	# Grok the payload
	if ($frame{control}) {
		if ($frame{type} == SYN_STREAM) {
			%frame = $self->read_syn_stream (%frame);
		} elsif ($frame{type} == SYN_REPLY) {
			%frame = $self->read_syn_reply (%frame);
		} elsif ($frame{type} == SETTINGS) {
			%frame = $self->read_settings (%frame);
		} elsif ($frame{type} == PING) {
			%frame = $self->read_ping (%frame);
		} elsif ($frame{type} == GOAWAY) {
			%frame = $self->read_goaway (%frame);
		} else {
			# We SHOULD ignore these, if we did implement everything
			# that we MUST implement.
			die 'Not implemented: Unsupported control frame '.$frame{type};
		}
	}

	return %frame;
}

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<http://www.chromium.org/spdy/spdy-protocol/spdy-protocol-draft3> -- Protocol specification

=item *

L<Net::SPDY::Session> -- SPDY session implementation

=item *

L<Net::SPDY::Compressor> -- SPDY header compression

=back

=head1 CONTRIBUTING

Source code for I<Net::SPDY> is kept in a public GIT repository.
Visit L<https://github.com/lkundrak/net-spdy>.

Bugs reports and feature enhancement requests are tracked at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Net::SPDY>.

=head1 COPYRIGHT

Copyright 2012, Lubomir Rintel

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Lubomir Rintel C<lkundrak@v3.sk>

=cut

1;
