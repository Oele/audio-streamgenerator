#! /usr/bin/env perl

use strict;
use warnings;
use Pod::Markdown::Github;
use FindBin qw($Bin);

my $parser = Pod::Markdown::Github->new;

open(my $fh, ">$Bin/../README.md");
$parser->output_fh(*$fh);
$parser->parse_file("$Bin/../lib/Audio/StreamGenerator.pm");
close $fh;
