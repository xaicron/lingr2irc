package App::Lingr2IRC;

use strict;
use warnings;
use 5.001001;
our $VERSION = 'v0.0.1';

use AnyEvent;
use AnyEvent::Lingr;
use AnyEvent::IRC::Client;

use Encode qw(encode_utf8);
use Log::Minimal;

$Log::Minimal::PRINT = sub {
    my ($time, $type, $message, $trace, $raw_message) = @_;
    print STDERR "$time [$type] $message\n";
};

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
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has password => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has session => (
    is => 'rw',
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
        session  => $self->session,
        api_key  => $self->api_key, # optional
        on_error => sub {
            my ($msg) = @_;

            warnf 'Lingr error :%s', $msg;

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

            infof 'joined rooms:';
            for my $room (@$rooms) {
                infof '  %s', $room->{id};
                $self->join_channel(
                    $self->bot_name,
                    $self->_get_channel_by_room($room->{id}),
                    1,
                );
            }
        },
        on_event => sub {
            my ($event) = @_;
#            use Data::Dumper;
#            warn Dumper $event;
            if (my $msg = $event->{message}) {
                my $nick    = $msg->{speaker_id};
                my $channel = $self->_get_channel_by_room($msg->{room});
                my $command = 'PRIVMSG';
                if ($msg->{type} eq 'bot') {
                    $command = 'NOTICE';
                }
                else {
                    # said from IRC
                    if (!$msg->{local_id} && $nick eq $self->user) {
                        return;
                    }
                }

                $self->join_channel($nick, $channel);
                for my $line (split /\r?\n/ms, $msg->{text}) {
                    $self->send($nick, $channel, $command, encode_utf8 $line);
                }
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
            infof 'signal received!';
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
                warnf 'connect error: %s', $err;
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
        critf 'failed join to %s (%s)', $channel, $nick;
        return;
    }
    $self->_irc_client_map->{$nick}{channel_map}{$channel} = 1;
    infof 'join channel: %s (%s)', $channel, $nick;
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
