#!/usr/bin/perl
package GPSTestRule;

use strict;
use warnings;

our $VERSION = qw/0.0.1/;

use Moose;
use Replay::Types;
with 'Replay::Role::BusinessRule' => { -version => 0.02 };

has '+name' => ( default => __PACKAGE__ );

sub match {
    my ( $self, $message ) = @_;
    return $message->{MessageType} eq 'GPS';
}

sub window {
    my ( $self, $message ) = @_;
    return 'alltime';
}

sub key_value_set {
    my ( $self, $message ) = @_;
    return "current" => { when => $message->{ReceivedTime}, %{$message->{Message}} };
}

sub compare {
    my ( $self, $aa, $bb ) = @_;
    return ( $aa || 0 ) <=> ( $bb || 0 );
}

sub reduce {
    my ( $self, $emitter, @state ) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
}

1;
