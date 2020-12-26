package Audio::StreamGenerator;

use strict;
use warnings;
use Data::Dumper;
use Log::Log4perl qw(:easy);

autoflush STDERR;

Log::Log4perl->easy_init($DEBUG);

my $logger = Log::Log4perl->get_logger('Audio::StreamGenerator');


sub new {
    my ( $class, $args ) = @_;
    my @mandatory_keys = qw (
        get_new_source
        normal_fade_seconds
        skip_fade_seconds
        sample_rate
        channels_amount
        max_vol_before_mix_fraction
        out_fh
    );

    my @optional_keys = qw(
        run_every_second
    );

    foreach my $key (@mandatory_keys) {
        die "value for $key is missing" if !defined( $args->{$key} );
    }
    my %key_lookup = map {$_ => 1} ( @mandatory_keys, @optional_keys );

    foreach my $key ( keys %$args ) {
        die "unknown argument '$key'"
            if !defined($key_lookup{$key});
    }

    my %self = %$args{ @mandatory_keys, @optional_keys };

    bless \%self, $class;
}

sub stream {
    my $self = shift;

    $self->{source} = $self->_do_get_new_source();
    $self->{buffer} = [];
    $self->{skip} = 0;

    my $short_clips_seen = 0;
    my $maxint           = 32767;

    my @channels;
    push @channels, $_ for 0...($self->{channels_amount}-1);

    while (1) {

        if ( eof( $self->{source} ) || $self->{skip} ) {

            if ($self->{skip}) {
                $logger->info('shortening buffer for skip...');
                pop @{ $self->{buffer} }
                    for 0 ... ( $self->{sample_rate} * ( $self->{normal_fade_seconds} - $self->{skip_fade_seconds} ) );
            }

            close( $self->{source} );
            my $old_elapsed_seconds = $self->{elapsed} / $self->{sample_rate};
            $self->{source} = $self->_do_get_new_source();

            $logger->info("old_elapsed_seconds: $old_elapsed_seconds");
            if ( $old_elapsed_seconds < ( $self->{normal_fade_seconds} * 2 ) ) {
                $short_clips_seen++;
                if ( $short_clips_seen >= 2 ) {
                    $logger->info('not mixing');
                    next;
                } else {
                    $logger->info("short, but mixing anyway because short_clips_seen is $short_clips_seen and old_elapsed_seconds is $old_elapsed_seconds");
                }
            } else {
                $short_clips_seen = 0;
                $logger->info('mixing');
            }

            my $index                  = 0;
            my $last_loud_sample_index = -1;
            my $threshold              = $maxint * $self->{max_vol_before_mix_fraction};
            my $max_old                = 0;
            foreach my $sample ( @{ $self->{buffer} } ) {
                foreach (@channels) {
                    my $single_sample = $sample->[$_];
                    $single_sample *= -1 if $single_sample < 0;
                    if ( $single_sample >= $threshold ) {
                        $last_loud_sample_index = $index;
                    }
                    if ( $single_sample > $max_old ) {
                        $max_old = $single_sample;
                    }
                }
                $index++;
            }

            $logger->info("last loud sample index: $last_loud_sample_index of " . scalar( @{ $self->{buffer} } ) );
            $logger->info("loudest sample value: $max_old");

            my @new_buffer;
            while ( @new_buffer < @{ $self->{buffer} } ) {
                my $sample = $self->_get_sample();
                last if !defined($sample);
                push( @new_buffer, $sample );
            }

            my @max   = (0) x $self->{channels_amount};
            my $total = scalar( @{ $self->{buffer} } );
            $index = -1;
            foreach my $sample ( @{ $self->{buffer} } ) {
                $index++;
                my $togo = $total - $index;

                my $mod = $index % $self->{sample_rate};

                my $full_second;
                if ( !( $index % $self->{sample_rate} ) ) {
                    $full_second = $index / $self->{sample_rate};
                }

                if ( !$self->{skip} && $index <= $last_loud_sample_index ) {
                    if ( defined($full_second) ) {
                        $logger->info("skipping second $full_second...");
                    }
                    next;
                }

                if ( defined $full_second ) {
                    $logger->info("mixing second $full_second...");
                }

                if ($self->{skip}) {
                    my $fraction = $togo / $total;
                    foreach my $single_sample (@$sample) {
                        $single_sample *= $fraction;
                    }
                }

                if ( @new_buffer >= $togo ) {
                    my $newsample = shift @new_buffer;

                    for my $channel (@channels) {
                        $sample->[$channel] += $newsample->[$channel];
                    }
                }


                foreach my $channel (@channels) {
                    my $value = $sample->[$channel];
                    $value *= -1 if $value < 0;
                    if ( $value > $max[$channel] ) {
                        $max[$channel] = $value;
                    }
                }
            }

            push( @{ $self->{buffer} }, @new_buffer );

            my $channel = 0;

            foreach my $channel (@channels) {
                $logger->info( "channel $channel needs volume adjustment" )
                   if ( $max[$channel] > $maxint );
            }

            foreach my $sample ( @{ $self->{buffer} } ) {
                for my $channel (@channels) {
                    if ( $max[$channel] > $maxint ) {
                        $sample->[$channel] =
                            ( $sample->[$channel] / $max[$channel] ) * $maxint;
                    }
                }
            }

            $self->{skip} = 0;

        }

        while ( @{ $self->{buffer} } < ( $self->{normal_fade_seconds} * $self->{sample_rate} ) ) {
            my $sample = $self->_get_sample();
            last if !defined($sample);
            push( @{ $self->{buffer} }, $sample );
        }

        $self->_send_one_sample();

        if ( !( $self->{elapsed} % $self->{sample_rate} )
            && defined( $self->{run_every_second} ) )
        {
            $self->{run_every_second}($self);
        }

    }

}

sub get_elapsed_samples {
    my $self = shift;
    return $self->{elapsed}
}

sub get_elapsed_seconds {
    my $self = shift;
    return $self->{elapsed}/$self->{sample_rate}
}


sub _send_one_sample {
    my $self   = shift;
    my $sample = shift @{ $self->{buffer} };
    my $fh = $self->{out_fh};
    print $fh map { pack 's*', $_ } @$sample;
}

sub _get_sample {
    my $self = shift;
    return undef if eof( $self->{source} );
    my $data;
    read( $self->{source}, $data, $self->{channels_amount} * 2 );
    $self->{elapsed}++;

    if ( length($data) == ( $self->{channels_amount} * 2 ) ) {
        my @sample;
        while ( length($data) ) {
            my $bytes_this_sample = substr( $data, 0, $self->{channels_amount} * 2, '' );
            push( @sample, unpack 's*', $bytes_this_sample );
        }
        return \@sample;
    } else {
        my @sample = (0) x ( $self->{channels_amount} * 2 );
        return \@sample;
    }
}

sub _do_get_new_source {
	my $self = shift;
	$self->{elapsed}  = 0;
    return $self->{get_new_source}();
}

sub skip {
    my $self = shift;
    $self->{skip} = 1
}

1;
