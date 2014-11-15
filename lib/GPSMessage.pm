#!/usr/bin/perl

package GPSMessage;

use strict;
use warnings;

our $VERSION = qw/0.0.1/;

use Moose;
extends('Replay::Message');
with qw/Replay::Envelope/;

has '+MessageType' => ( default => 'GPS' );
has '+version'     => ( default => '1' );
has 'Time_UTC'     => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

has 'Velocity' => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

has 'Heading' => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

has 'Latitude' => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

has 'Longitude' => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

1;
