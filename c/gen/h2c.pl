#! /usr/bin/perl -CSD -l -w

use strict;
use warnings;
use Data::Dumper;               # for debugging
# use Getopt::Long;             # not yet needed

sub trim {
    $_ = shift // $_;
    s/^\s*//;
    s/\s*$//;
    return $_;
}

# if there is a filename in @ARGV use it, otherways take "test.h"
my $name = shift // "test.h";

# read whole file
$_ = do {
    local $/ = undef;
    open my $f, '<', $name or die "Could not open \"$name\": $!\n";
    <$f>;
};
