#! /usr/bin/perl -CSD

use strict;
use warnings;
use Data::Dumper;

use constant {
    DEBUG => 0,
};

# workaround for -l switch: automatic line-endings
chomp $/;
$\ = "\n";


my $args;

sub trim {
    local $_ = shift // $_;
    s/^\s*//;
    s/\s*$//;
    return $_;
}

################################################################################
# Definitions                                                                  #
################################################################################
# this is a list of keywords and modifiers
# they are used to compare against in variable interpretation
my @keywords = qw(
    const
    enum
    extern
    register
    signed
    static
    struct
    typedef
    union
    unsigned
    volatile
);

################################################################################
# Utils                                                                        #
################################################################################
# prints the usage of this script with perldoc
sub usage {
    system "perldoc $0";
    exit 1;
}

# returns the basename of a given path
#
# input:  string to generate the basename from
# output: the basename
sub basename {
    return $1 if shift =~ /\/?([^\/]+)$/;
    return undef;
}

# compares to given arrays on equality
#
# input:  two arrays
# output: 1 or 0 depending on the result of the comparison
sub eq_array($$) {
    my ($ref1, $ref2) = @_;

    # test both args arrays on equality by joining both arrays with
    # a '\a' char and comparing the resulting strings with each
    # other.
    # that's a bit dirty but its readability and maintainability is
    # good.
    local $" = "\a";
    return "@$ref1" eq "@$ref2";
}

# input:  filename of file to open
# output: lines of the file as scalar
sub get_file_contents(;$) {
    local $_ = shift // $_;

    return do {
        local $/ = undef;
        open my $f, '<', $_ or die "Could not open \"$_\": $!\n";
        <$f>;
    };
}

# shrink multiline preprocessor commands into one line
# remove block comments
#
# input:  lines of the file as scalar
# output: file contents spiltted at '\n'
sub prepare_file_contents(;$) {
    local $_ = shift // $_;

    s/\s*\\\n\s*/ /gs;
    s/\/\*.*?\*\// /gs;

    return split /\s*\n/;
}

# search lines with preprocessor commands
# remove single line comments
#
# input:  lines of file to parse
# output: reference to a list containing the indexes where
#         preprocessor commands were found
sub get_prep_lines {
    return [ grep {
        $_[$_] =~ s/\s*\/\/.*$/ /;
        $_[$_] =~ /^\s*#/;
    } 0 .. $#_ ];
}

# removes all lines with preprocessor commands
#
# input:  line numbers where preprocessor commands were found
sub remove_prep_lines($$) {
    my ($prep, $lines) = @_;

    return map {
        $lines->[$_] = ''
    } @$prep;
}

# creates certain hashes
#
# input:  the name of the hash you want to have
# output: the hash
sub create_hash($;$$) {
    my ($type, $name, $mod) = @_;

    return {
        # modifier of function definition
        mod => $mod,
        name => $name,
        args => [],
        # did the script generate variable names automatically?
        set => 0,
    } if $type eq 'func';

    return {
        added => [],
        error => [],
    } if $type eq 'compare';

    return {
        includes => {},
        functions => {},
        raw => '',
    } if $type eq 'base';

    return {
        raw => [@ARGV],
        verbose => 0,
        rl_tabs => 0,
        ln_tab => 4,
        licence => '',
        output => '',
        help => 0,
        fname => '',
        base => '',
        tab => '    ' ,
    } if $type eq 'args';
}

# gets all includes
#
# input:  1. line numbers where preprocessor commands were found
#         2. the lines themselves
# output: a hash containing all includes
sub get_includes($$) {
    my ($prep, $lines, %return) = @_;

    for (@$prep) {
        if ($lines->[$_] =~ /^\s*#\s*include\s*(\S+)/) {
            local $_ = $1;
            $return{$_} = 1;
        }
    }

    return \%return;
}

# get the variable types of a given array of variable declarations
#
# input:  array of variable declarations
# output: their type
sub get_var_type {
    my @args = @{shift // $_};

    s/\s+\w+$// for @args;

    return \@args;
}

# gets the current variable decleration
#
# input:  1. the function hash which we currently build
#         2. a reference to the current $var -> auto generating variable names
#         3. the line to parse
# output: nothing, the function changes argument 1 on the fly
sub get_function_arg($$;$) {
    my ($new, $var, @tmp) = (shift, shift);
    local $_ = shift // $_;

    $_ = trim;
    s/\s*,\s*//;

    for my $tkn (split /\s+/, $_) {
        # break if there aren't any variable declarations
        last if /^void$/;

        # remove stars temporary
        $tkn =~ s/\*//g;

        next if /__attribute__/;
        push @tmp, $tkn if not grep { $_ eq $tkn } @keywords;
    }

    # write parameters:
    # if length(@tmp) <= 1, only a type is given
    # otherways a name is given as well.
    $new->{set} = not @tmp - 1;
    push @{$new->{args}}, ($new->{set} ? "$_ ".$$var++ : $_);
}

# gets the output stream where we write to
# the file will be closed implicit so you can safely kill the process to prevent
# writing to disk.
#
# output: a filehandle which can be selected
sub get_output_stream {
    return \*STDOUT unless $args->{output};

    open my $f, '>>', $args->{output} or
        die "Could not open \"$args->{output}\": $!\n";
    return $f;
}

################################################################################
# parse files
################################################################################
# parses a given file
#
# input:  filename
# output: a hash containing all includes and function information
sub parse_file(;$) {
    my $return = create_hash 'base';
    $return->{raw} = $_ = get_file_contents shift // $_;
    @_ = prepare_file_contents;
    my $prep = get_prep_lines @_;
    $return->{includes} = get_includes $prep, \@_;
    remove_prep_lines $prep, \@_;

    for (my $i = 0; $i < @_; ++$i) {
        # the only parts in this array starting with no indention level and
        # ending with a open bracket are function declarations
        if ($_[$i] =~ /^(\w+)\s*\(/) {
            my ($var, $name) = ('a', $1);
            my $new = create_hash 'func', $name, $_[$i - 1];

            get_function_arg $new, \$var, $_[$i] while $_[++$i] !~ /^\)/;
            $new->{mod} =~ s/^extern\s+//;

            $return->{functions}->{$name} = $new;
        }
    }

    print '-' x qx(tput cols) . "\n" . "parse_file:\n" . Dumper $return if DEBUG;

    return $return;
}




################################################################################
# compare                                                                      #
################################################################################
sub compare_amount($$$) {
    my ($curh, $src, $return) = @_;

    if (not exists $src->{functions}->{$curh->{name}}) {
        $src->{functions}->{$curh->{name}} = $curh;
        push @{$return->{added}}, $curh->{name};
        return 1;
    }

    return 0;
}

sub compare_mod_args($$$) {
    my ($curh, $curs, $return) = @_;

    if ($curs->{mod} ne $curh->{mod} or @{$curs->{args}} != @{$curh->{args}}) {
        push @{$return->{error}}, {
            name => $curh->{name},
            reason => 'Different modifiers or different argument length',
        };
        return 1;
    }

    return 0;
}

sub compare_args($$$) {
    my ($curh, $curs, $return) = @_;

    push @{$return->{error}}, {
        name => $curh->{name},
        reason => 'Different argument order',
    } if not eq_array get_var_type($curs->{args}), get_var_type($curh->{args});
}

sub compare($$) {
    my ($hdr, $src) = @_;

    my $return = create_hash 'compare';
    for (values %{$hdr->{functions}}) {
        next if compare_amount $_, $src, $return;
        next if compare_mod_args $_, $src->{functions}->{$_->{name}}, $return;
        compare_args $_, $src->{functions}->{$_->{name}}, $return;
    }

    print '-' x qx(tput cols) . "\n" .
          "compare:\n" . Dumper $return->{error} if DEBUG;
    return $return;
}



################################################################################
# dump                                                                         #
################################################################################
sub dump_success($) {
    my $todo = shift // $_;

    unless (@{$todo->{added}}) {
        print "Nothing added" if $args->{verbose};
        return;
    }

    print "Added the following functions:";
    print "> $_" for sort @{$todo->{added}};
}

sub dump_errors($) {
    my $todo = shift // $_;

    unless (@{$todo->{error}}) {
        print "No conflicts found!" if $args->{verbose};
        return;
    }

    my $len = (sort {$b <=> $a} map {length $_->{name}} @{$todo->{error}})[0];

    print "Conflicts found:";
    for (sort { $a->{name} cmp $b->{name} } @{$todo->{error}}) {
        printf "> %-*s%s\n", $len + 4, "$_->{name}:", $_->{reason}
    }
    print '';
}

sub dump_licence {
    return unless $args->{licence};

    print get_file_contents $args->{licence};
}

sub dump_function(;$) {
    local $_ = shift // $_;
    local $" = ",\n$args->{tab}";

    print "\n$_->{mod}";
    print "$_->{name}(";
    print "$args->{tab}@{$_->{args}}";
    print ") {\n$args->{tab}/* TODO */\n}\n";
}

sub dump_header($$) {
    my ($data, $base) = @_;

    print "/* Automatically generated by h2c.pl */\n";
    print "#include \"$base\"\n";
    print "#include $_" for keys %{$data->{includes}};
    print "\n";
}

sub dump_all($$) {
    my ($data, $base) = @_;
    dump_header $data, $base;
    dump_function for values %{$data->{functions}};
}

sub dump_add($$) {
    my ($data, $todo) = @_;

    dump_function $data->{functions}->{$_} for @{$todo->{added}};
}

sub to_stdout {
    select STDOUT;
}

sub to_stderr {
    select STDERR;
}

sub to_stream($) {
    select shift;
}

################################################################################
# parse args                                                                   #
################################################################################
sub eval_args($) {
    my $args = shift;

    usage if $args->{help} or not $args->{fname};

    $args->{base} = basename $args->{fname};
    $args->{fname} =~ /\/?([^\/]+)$/ and $args->{base} = $1;
    # ($args->{output} = $args->{fname}) =~ s/\.h$/.c/ if $args->{output} eq '';

    $args->{tab} = $args->{rl_tabs} ? "\t" : ' ' x $args->{ln_tab};

    print '-' x qx(tput cols) . "\neval_args\n" . Dumper $args if DEBUG;

    return $args;
}

sub parse_args(@) {
    my $args = create_hash 'args';
    local @_ = @{$args->{raw}};

    # while (shift) does not set $_ due to some strange reason...
    while ($_ = shift) {
        $args->{help} = 1, next if $_ eq '-h' or $_ eq '--help';
        $args->{verbose} = 1, next if $_ eq '-v' or $_ eq '--verbose';
        $args->{rl_tabs} = 1, next if $_ eq '-r' or $_ eq '--real-tabs';

        $args->{ln_tab} = $1, next if /^--tab-length=(\d+)$/;
        $args->{licence} = $1, next if /^--licence=(.+)$/;
        $args->{output} = $1, next if /^--output=(.+)$/;

        $args->{ln_tab} = shift, next if /^-t$/ or /^--tab-length$/;
        $args->{licence} = shift, next if /^-l$/ or /^--licence$/;
        $args->{output} = shift, next if /^-o$/ or /^--output$/;

        $args->{fname} = $_;
    }

    print '-' x qx(tput cols) . "\nparse_args\n" . Dumper $args if DEBUG;
    return eval_args $args;
}

################################################################################
# main                                                                         #
################################################################################
sub main {
    $args = parse_args;
    my $hdr = parse_file $args->{fname};
    my $todo;

    if (not -e $args->{output}) {
        to_stream get_output_stream;
        dump_all $hdr, $args->{base};
        $todo = {
            added => [keys %{$hdr->{functions}}]
        };
    } else {
        my $src = parse_file $args->{output};
        $todo = compare $hdr, $src;

        to_stream get_output_stream;
        dump_add $hdr, $todo if -r $args->{output} and -w $args->{output};
    }

    to_stderr;
    dump_success $todo;
    dump_errors $todo;
    to_stdout;
}

main;


################################################################################
# help                                                                         #
################################################################################
__END__

=head1 NAME

    h2c.pl

=head1 SYNOPSIS

              h2c.pl [option(s)] <header_file>
    perl -CSD h2c.pl [option(s)] <header_file>

=head1 DESCRIPTION

=over 4

`h2c.pl' is a tool which automatically generates a c source file from a given
header file.
By default the script prints everything to stdout and it is up to you to
redirect it to a file. There is a flag which can change this behaviour.
Standard indention is 4 spaces.
If you wish you can add a licence, which will be included at the top of the
file.

`h2c.pl` is able to recognize differences between a given header file and its
source file and notify the user about conflicts.

Metainformation e.g. summaries or conflicts are printed to STDERR, so they will
not hinder shell level redirections.

=back

=head1 OPTIONS

    -h | --help
        show this page

    -l | --licence <filename>
        add the given licence in comments at the top of the output

    -o | --output <filename>
        you can specify an output filename,
        or if <filename> equals 'none', no file is written

    -r | --real-tabs
        use real tabs for indention

    -t | --tab-length <positiv_integer>
        use spaces to indent, default is 4

    -v | --verbose
        print output also to stdout

=head1 AUTHOR

    Manuel Johannes Messner

=cut


