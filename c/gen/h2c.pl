#! /usr/bin/perl -CSD

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;               # for debugging

use constant {
    DEBUG => 1,
};

# workaround for -l switch: automatic line-ending
chomp $/;
$\ = "\n";

# we use getopt for command line parameter handling
my %args;
GetOptions(\%args, qw(
    tab-length|t=i
    real-tabs
    verbose|v
    output|o=s
    licence|l=s
    )
);

my $tab = $args{'real-tabs'} ? "\t" : ' ' x ($args{'tab-length'} // 4);

sub trim {
    local $_ = shift // $_;
    s/^\s*//;
    s/\s*$//;
    return $_;
}

# print usage if -h or --help is in @ARGV
print "Usage h2c.pl <filename>\n", exit if grep { /--?h(?:help)?/ } @ARGV;

# if there is a filename in @ARGV use it, otherways take "test.h"
my $name = shift // "test.h";

# read whole file
$_ = do {
    local $/ = undef;
    open my $f, '<', $name or die "Could not open \"$name\": $!\n";
    <$f>;
};

# preprocessor: shrink multiline macros into one line
s/\s*\\\n\s*/ /gs;

# comments: remove block comments
s/\/\*.*?\*\// /gs;

# gcc: remove GTY macro structs
# s/struct\s+(?:[\w-]+\s+)*GTY\(\(.*?\){2,}\s*(?:[\w-]+\s*)\{.*?\}/ /gs;
s/(?:struct|union)\s+.*?\{.*?\}/ /gs;

# pick up all includes, using hashes because they are unique
my %includes;

# split file into lines and iterate over each line
my @lines = split /\n/;
for (@lines) {
    # comments: remove single line comments
    s/\/\/.*$/ /;

    # preprocessor: remove preprocessor lines and pick up includes
    if (/^\s*#\s*(\w+)\s*(.*)/) {
        if ($1 eq 'include') {
            $includes{$2} = 1;
        } elsif ($1 =~ /^if/) {
            # TODO:
        }
        $_ = '';
    }
}

# pick up all function declarations
my @functions;

# reserved words for function parameter interpretation
my @keywords = qw(unsigned signed static const volatile register
              extern struct union);

# final commands to work with
my @commands = split /;/, join ' ', @lines;
s/\n//gs for @commands;

# logical separation
# loop through all commands
for (@commands) {
    # skip typedefs, GTY macros and blocks from enums, ...
    next if /^\s*typedef/;
    next if /GTY\(\(.*?\){2,}/;
    next if /\{.*?\}/;

    # searching for function definitions
    if (/\s*((?:[\w-]+\s+)+)(\w+)\s*\(.*?\)\s*/) {
        # auto generate variables if no name is given
        my $tmp = 'a';

        my %func = (
            mod => (trim $1),
            name => (trim $2),
            args => [],
        );
        # get arguments and save them in %func
        if (/$2\s*\((.*?)\)/) {
            for (split /,/, $1) { # move stars to type s/\s*(\*+)\s*/$1 /g;

                $_ = trim;

                # remove stars temporary for paramter interpretation
                (my $var = $_) =~ s/\*//g;
                my @tmp;

                # split parameter declaration at spaces
                for my $word (split /\s+/, $var) {
                    # pick all unknown words (they are types or names)
                    push @tmp, $word if not grep { $_ eq $word } @keywords;
                }

                # save parameter
                # if length(@tmp) <= 1, only a type is given
                # otherways a name is given, too
                push $func{args}, (@tmp <= 1 ? "$_ " . $tmp++ : $_);
            }

            # save function
            push @functions, \%func;
        }
    }
}

# build output
# we use arrays because of configurability
my @out;

# insert the licence if the according flag is set
if ($args{licence}) {
    $_ = trim do {
        local $/ = undef;
        open my $f, '<', $args{licence}
            or die "Could not open \"$args{licence}\": $!\n";
        <$f>;
    };

    push @out, "/*";
    push @out, $_;
    push @out, "*/";
    push @out, '';
}

push @out, qq(/* Automatically generated by h2c.pl */\n);
push @out, qq(#include "$name");
push @out, qq(#include $_) for keys %includes;
for (@functions) {
    local $" = ",\n$tab";
    push @out, '';
    push @out, $$_{mod};
    push @out, "$$_{name}(";
    push @out, "$tab@{$$_{args}}";
    push @out, ')';
    push @out, '{';
    push @out, "$tab/* TODO */";
    push @out, '}';
}

# if output flag is set and given name is not 'none': save file
if (not $args{output} or $args{output} ne 'none') {
    # save output to file
    # use the same filename as the header file with exchanged ending
    # or if given the name from command line
    my $outfile = $args{output} // $name;
    $outfile =~ s/\.h$/.c/ if $outfile eq $name;

    open my $f, '>', $outfile or die "Could not open $outfile: $!\n";
    print $f $_ for @out;
    close $f;
}

# print output to stdout if verbosity flag is set
if ($args{verbose}) {
    print $_ for @out;
}

