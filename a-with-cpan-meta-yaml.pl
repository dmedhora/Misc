#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Basename qw(basename);
use Text::CSV;
use CPAN::Meta::YAML;

sub usage {
    die <<"USAGE";
Usage:
  $0 --input csv_file --output output.ind --config cmod_indexer.yml

Example:
  $0 --input NTQBSWHF_.data.csv --output output.ind --config cmod_indexer.yml
USAGE
}

my ($input, $output, $config_path);

GetOptions(
    'input=s'  => \$input,
    'output=s' => \$output,
    'config=s' => \$config_path,
) or usage();

usage() unless defined $input && defined $output && defined $config_path;

open my $in,  '<:raw', $input  or die "Cannot open input '$input': $!\n";
open my $out, '>:raw', $output or die "Cannot open output '$output': $!\n";

my $group_filename = $input;
my $base = basename($input);

# ---- Load YAML config using CPAN::Meta::YAML (no YAML::XS required) ----
my $yaml_text = do {
    open my $fh, '<', $config_path
      or die "Cannot open config '$config_path': $!\n";
    local $/;
    <$fh>;
};

my $docs = CPAN::Meta::YAML->read_string($yaml_text)
  or die "Failed to parse YAML config '$config_path'\n";

my $cfg = $docs->[0];   # first YAML document
die "Config '$config_path' is empty or invalid\n" unless ref($cfg) eq 'HASH';

die "Config '$config_path' must contain 'profiles' as a list\n"
    unless ref($cfg->{profiles}) eq 'ARRAY';

# ---- Select matching profile ----
my $profile;
for my $p (@{ $cfg->{profiles} }) {
    next unless ref($p) eq 'HASH';
    my $re = $p->{match} // '';
    next unless length $re;
    if ($base =~ /$re/i) {
        $profile = $p;
        last;
    }
}
die "No profile matched input '$base' in config '$config_path'\n" unless $profile;

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
my $data_start_byte = tell($in);

while (1) {
    my $record_start_byte = tell($in);
    my $line = <$in>;
    last unless defined $line;

    # Compute record length excluding newline
    my $len = length($line);
    if ($line =~ /\r\n\z/) {
        $len -= 2;
    } elsif ($line =~ /\n\z/ || $line =~ /\r\z/) {
        $len -= 1;
    }

    # Trim line endings for parsing
    $line =~ s/[\r\n]+\z//;

    # Skip completely empty lines (optional)
    next if $line eq '';

    $csv->parse($line) or do {
        my $err = $csv->error_diag();
        die "CSV parse error at input offset " . ($record_start_byte - $data_start_byte) .
            ": $err\nLine: $line\n";
    };

    my @f = $csv->fields();

    # Print mapped fields only
    for my $colnum (@mapped_cols) {
        my $idx   = $colnum - 1;                 # convert 1-based column -> 0-based index
        my $name  = $map->{$colnum};
        my $value = defined $f[$idx] ? $f[$idx] : '';

        print {$out} "GROUP_FIELD_NAME:$name\n";
        print {$out} "GROUP_FIELD_VALUE:$value\n";
    }

    my $current_data_byte_offset = $record_start_byte - $data_start_byte;

    print {$out} "GROUP_OFFSET:$current_data_byte_offset\n";
    print {$out} "GROUP_LENGTH:$len\n";
    print {$out} "GROUP_FILENAME:$group_filename\n";
}

close $in  or die "Error closing input: $!\n";
close $out or die "Error closing output: $!\n";

