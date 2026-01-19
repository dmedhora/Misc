#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Basename qw(basename);
use Text::CSV;
use YAML::XS qw(LoadFile);

sub usage {
    die <<"USAGE";
Usage:
  $0 --input csv_file --output output.ind --config cmod_indexer.yml

Example:
  $0 --input NTQBSWHF_.data.csv --output output.ind --config cmod_indexer.yml
USAGE
}

my ($input, $output, $config);
GetOptions(
    'input=s'  => \$input,
    'output=s' => \$output,
    'config=s' => \$config,
) or usage();

usage() unless defined $input && defined $output && defined $config;

open my $in,  '<:raw', $input  or die "Cannot open input '$input': $!\n";
open my $out, '>:raw', $output or die "Cannot open output '$output': $!\n";

my $group_filename = $input;
my $filebasename = basename($input);

# ---- Load YAML config ----
my $cfg = LoadFile($config);
die "Config '$config' must contain 'configs' as a list\n"
    unless ref($cfg) eq 'HASH' && ref($cfg->{configs}) eq 'ARRAY';

# ---- Select matching profile ----
my $profile;
for my $p (@{ $cfg->{configs} }) {
    next unless ref($p) eq 'HASH';
    my $re = $p->{match} // '';
    next unless length $re;
    if ($filebasename =~ /$re/i) {
        $profile = $p;
        last;
    }
}
die "No profile matched input '$filebasename' in config '$config'\n" unless $profile;

my $delim = $profile->{delimiter} // ';';
my $map   = $profile->{map};
die "Profile must contain a 'map' hash\n" unless ref($map) eq 'HASH';

# Build sorted list of (colnum, outname). colnum is 1-based in YAML.
my @mapped_cols = sort { $a <=> $b } grep { /^\d+$/ && $_ >= 1 } keys %$map;
die "Profile map is empty or invalid\n" unless @mapped_cols;

my $csv = Text::CSV->new({
    binary              => 1,
    sep_char            => $delim,
    quote_char          => '"',
    escape_char         => '"',
    allow_loose_quotes  => 1,
    allow_loose_escapes => 1,
}) or die "Text::CSV->new() failed\n";

# ---- Skip header line (always 1st line) ----
my $header = <$in>;
die "Input '$input' is empty (no header line found)\n" unless defined $header;

# Base offset after header so first data record offset is 0
my $start_of_data = tell($in);

while (1) {
    my $start_of_line  = tell($in);
    my $line = <$in>;
    last unless defined $line;

    # Compute record length excluding newline
    my $len = length($line);
    if ($line =~ /\r\n\z/) { $len -= 2; }
    elsif ($line =~ /\n\z/ || $line =~ /\r\z/) { $len -= 1; }

    $line =~ s/[\r\n]+\z//;
    next if $line eq '';

    $csv->parse($line) or do {
        my $err = $csv->error_diag();
        die "CSV parse error at input offset " . ($start_of_line - $start_of_data) . ": $err\nLine: $line\n";
    };
    my @f = $csv->fields();

    # Print mapped fields only
    for my $colnum (@mapped_cols) {
        my $idx   = $colnum - 1;                  # convert to 0-based array index
        my $name  = $map->{$colnum};
        my $value = defined $f[$idx] ? $f[$idx] : '';

        print {$out} "GROUP_FIELD_NAME:$name\n";
        print {$out} "GROUP_FIELD_VALUE:$value\n";
    }

    my $data_pos_now_at = $start_of_line - $start_of_data;
    print {$out} "GROUP_OFFSET:$data_pos_now_at\n";
    print {$out} "GROUP_LENGTH:$len\n";
    print {$out} "GROUP_FILENAME:$group_filename\n";
}

close $in  or die "Error closing input: $!\n";
close $out or die "Error closing output: $!\n";
