package App::Lingr2IRC;

use strict;
use warnings;
use 5.001001;
use feature 'say';
our $VERSION = 'v0.0.1';

use AnyEvent;
use AnyEvent::Lingr;
use AnyEvent::IRC::Client;

use Encode qw(encode_utf8);

use Mouse;

has bot_name => (
    is      => 'rw',
    isa     => 'Str',
    default => 'lingrbot',
);

has irc_speaker_id => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has channel_prefix => (
    is      => 'rw',
    isa     => 'Str',
    default => '#lingr-',
);

has irc_server_host => (
    is      => 'ro',
    isa     => 'Str',
    default => 'localhost',
);

has irc_server_port => (
    is      => 'ro',
    isa     => 'Int',
    default => 6667,
);

has user => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has password => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has api_key => (
    is  => 'ro',
    isa => 'Str',
);

has lingr => (
    is  => 'ro',
    isa => 'AnyEvent::Lingr',
);

has _irc_client_map => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

sub BUILD {
    my $self = shift;

    my $lingr;
    $lingr = AnyEvent::Lingr->new(
        user     => $self->user,
        password => $self->password,
        api_key  => $self->api_key, # optional
        on_error => sub {
            my ($msg) = @_;

            say STDERR 'Lingr error: ', $msg;

            my $t; $t = AnyEvent->timer(
                after => 5,
                cb   => sub {
                    $lingr->start_session;
                    undef $t;
                },
            );
        },
        on_room_info => sub {
            my ($rooms) = @_;

            say 'joined rooms:';
            for my $room (@$rooms) {
                say "  $room->{id}";
                $self->join_channel(
                    $self->bot_name,
                    $self->_get_channel_by_room($room->{id}),
                    1,
                );
            }
        },
        on_event => sub {
            my ($event) = @_;
            if (my $msg = $event->{message}) {
                return unless $msg->{local_id}; # said from IRC
                my $channel = $self->_get_channel_by_room($msg->{room});
                $self->join_channel($msg->{nickname}, $channel);
                my $text = encode_utf8 $msg->{text};
                $self->send($msg->{nickname}, $channel, 'PRIVMSG', $text);
            }
        },
    );

    # TODO update_room_info

    $self->{lingr} = $lingr;
}

no Mouse;

sub run {
    my $self = shift;
    my $c = AnyEvent->condvar;
    my $w; $w = AnyEvent->signal(
        signal => 'INT',
        cb     => sub {
            say STDERR "signal received!";
            $c->broadcast;
            undef $w;
        },
    );
    $self->lingr->start_session;
    $c->wait;
    $self->disconnect_all;
}

sub disconnect_all {
    my $self = shift;
    for my $nick (keys %{ $self->_irc_client_map }) {
        $self->_irc_client_map->{$nick}{client}->disconnect;
    }
}

sub join_channel {
    my ($self, $nick, $channel, $is_bot) = @_;
    $self->_irc_client_map->{ $nick } ||= do {
        my $con = AnyEvent::IRC::Client->new;
        $con->reg_cb(connect => sub {
            my ($con, $err) = @_;
            if (defined $err) {
                say STDERR "connect error: $err";
                return;
            }
        });

        if ($is_bot) {
            # say irc -> lingr
            $con->reg_cb(publicmsg => sub {
                my ($con, $channel, $data) = @_;
                return unless $self->_is_sendable($data);
                my $room = $self->_get_room_by_channel($channel);
                my $msg  = $data->{params}[1];
                $self->lingr->say($room, $msg);
            });
        }

        $con->connect(
            $self->irc_server_host,
            $self->irc_server_port,
            { nick => $nick },
        );
        $con->enable_ping(10, sub {});

        { client => $con, channel_map => {} };
    };

    unless ($self->is_joined($nick, $channel)) {
        $self->_join_channel($nick, $channel);
    }
}

sub _join_channel {
    my ($self, $nick, $channel) = @_;
    unless ($self->_send_join($nick, $channel)) {
        say STDERR "[ERROR] failed join to $channel ($nick)";
        return;
    }
    $self->_irc_client_map->{$nick}{channel_map}{$channel} = 1;
    say "join channel: $channel ($nick)";
}

sub _send_join {
    my ($self, $nick, $channel) = @_;
    $self->_irc_client_map->{$nick}{client}->send_srv(JOIN => $channel);
}

sub is_joined {
    my ($self, $nick, $channel) = @_;
    $self->_irc_client_map->{$nick}{channel_map}{$channel} ? 1 : 0;
}

sub _get_room_by_channel {
    my ($self, $channel) = @_;
    my (undef, $room) = split '-', $channel, 2;
    return $room;
}

sub _get_channel_by_room {
    my ($self, $room) = @_;
    $self->channel_prefix.$room;
}

sub _is_sendable {
    my ($self, $data) = @_;
    return unless $data->{command} eq 'PRIVMSG';
    my ($nick) = split '!', $data->{prefix};
    return unless $nick eq $self->irc_speaker_id;
    return 1;
}

sub send {
    my ($self, $nick, $channel, $command, $msg) = @_;
    $self->_irc_client_map->{$nick}{client}->send_srv($command, $channel, $msg);
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

App::Lingr2IRC - blah blah blah

=head1 SYNOPSIS

  use App::Lingr2IRC;

=head1 DESCRIPTION

App::Lingr2IRC is

=head1 AUTHOR

xaicron E<lt>xaicron {at} cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2013 - xaicron

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
