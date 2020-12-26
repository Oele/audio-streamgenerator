## Name

Audio::StreamGenerator - create a 'radio' stream by mixing ('cross fading') multiple audio sources (files or anything that can be converted to PCM audio) and sending it to a streaming server (like Icecast)

## Synopsis

```perl
use strict;
use warnings;
use Audio::StreamGenerator;

my $out_command = q~
        ffmpeg -re -f s16le -acodec pcm_s16le -ac 2 -ar 44100 -i -  \
        -acodec libopus -ac 2 -b:a 160k -content_type application/ogg -format ogg icecast://source:hackme@localhost:8000/our_radio.opus \
        -acodec libmp3lame -ac 2 -b:a 192k -content_type audio/mpeg icecast://source:hackme@localhost:8000/our_radio.mp3 \
        -acodec aac -b:a 192k -ac 2 -content_type audio/aac icecast://source:hackme@localhost:8000/our_radio.aac
~;

my $out_fh;
open ($out_fh, '|-', $out_command);

sub get_new_source {
    my $fullpath = '/path/to/some/audiofile.flac';
    my @ffmpeg_cmd = (
            '/usr/bin/ffmpeg',
            '-i',
            $fullpath,
            '-af', $af_arg,
            '-loglevel', 'quiet',
            '-f', 's16le',
            '-acodec', 'pcm_s16le',
            '-ac', '2',
            '-ar', '44100',
            '-'
    );
    open($source, '-|', @ffmpeg_cmd);
    return $source;
}

sub run_every_second {
    # another second has passed, 
    my $streamert = shift;
    my $position = $streamert->get_elapsed_seconds();
    print STDERR "\rnow at position $position";
    if ([-some external event-]) {  # skip to the next song
        $streamert->skip()
    }
}

my $streamer = Audio::StreamGenerator->new({
    out_fh => $out_fh,
    get_new_source => \&get_new_source,
    run_every_second => \&run_every_second,
});

$streamer->stream();
```

## Description

This module creates a 'live' audio stream that can be broadcast using streaming technologies like Icecast or HTTP Live Streaming. 

It mixes multiple raw audio streams into one ongoing stream, mixing ('crossfading') them to one ongoing stream. 

Although there is nothing stopping you from using this to generate a file that can be played back later, its intended use is to create a 'radio' stream that can be streamed or 'broadcast' live on the internet. 

The module takes raw PCM audio from a file handle as input, and outputs raw PCM audio to another file handle. This means that an external program is necessary to decode (mp3/flac/etc) source files, and to encode & stream the actual output. For both purposes, ffmpeg is recommended - but anything that can produce and/or receive raw PCM audio should do. 

## Constructor Method

my $streamer = Audio::StreamGenerator->new( %options );

Creates a new StreamGenerator object and returns it. 

## Options

The following options can be specified:

```
KEY                             DEFAULT     MANDATORY
-----------                     -------     ---------
out_fh                          -           yes
get_new_source                  -           yes
run_every_second                -           no
normal_fade_seconds             5           no
skip_fade_seconds               3           no
sample_rate                     44100       no
channels_amount                 2           no
max_vol_before_mix_fraction     0.75        no
```

### Out\_Fh

The outgoing file handle - this is where the generated signed 16-bit little-endian PCM audio stream is sent to. 

### Get\_New\_Source

Reference to a sub that will be called initially to get the source + every time a source ends, to get a new one. Needs to return a readable filehandle that will output signed 16-bit little-endian PCM audio. 

### Run\_Every\_Second

This sub will be run after each second of playback, with the StreamGenerator object as an argument. This can be used to do things like updating a UI with the current playing position - or to call the skip() method if we need to skip to the next source. 

### Normal\_Fade\_Seconds

Amount of seconds that we want tracks to overlap. This is only the initial/max value - the mixing algorithm may choose to mix less seconds if the 'old' track ends with 'loud' samples.

### Skip\_Fade\_Seconds

When 'skipping' to the next song using the skip() method (for example, after a user clicked a "next song" button on some web interface), we mix less seconds than normally, simply because mixing 5+ seconds in the middle of the 'old' track sounds pretty bad. This value has to be lower than normal\_fade\_seconds. 

### Sample\_Rate

The amount of samples per second (both incoming & outgoing), normally this is 44100 for standard CD-quality audio. 

### Channels\_Amount

Amount of audio channels, this is normally 2 (stereo). 

### Max\_Vol\_Before\_Mix\_Fraction

When mixing 2 tracks, StreamGenerator needs to know what the last 'loud' sample of the old track is so that it can start the next song immediately after that - a 'blind' mix without this analysis sounds bad and unprofessional. This is expressed as a fraction of the maximum volume. 

## Methods

### Skip
    $streamer->skip();

'Skip' to the next track without finishing the current one. This can be called from the "run\_every\_second" sub, for example by checking whether a flag was set in a database, or whether a file exists. 

### Get\_Elapsed\_Samples

Get the amount of played samples in the current track - this can be called from the "run\_every\_second" sub. 

### Get\_Elapsed\_Seconds

Get the amount of elapsed seconds in the current track - in other words the current position in the track. This equals to get\_elapsed\_samples/sample\_rate . 
