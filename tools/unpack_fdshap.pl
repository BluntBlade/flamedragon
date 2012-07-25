#!/usr/bin/env perl

use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_END);

use constant INT16_SIZE => 2;
use constant INT32_SIZE => 4;
use constant DATA_OFF => 6;

sub output_pixel {
    my $x = shift;
    my $y = shift;
    my $pixels = shift;

    push @$pixels, (0) x (24 - scalar(@$pixels));

    my $text = join " ", map { sprintf("%02X", $_) } @$pixels;
    printf "pos=%02d,%02d pixels=[%s]\n", $x, $y, $text;
} # output_pixel

sub unpack_block {
    my $i = shift;
    my $block = shift;
    my $block_off = shift;
    my $end_off = shift;
    my $width = shift;
    my $height = shift;

    printf "block_index=$i\n";
    #printf ">> %08X %d\n", $block_off, $length;

    my $is_pixel = 0;
    my $repeat_pixel = 0;
    my $another_repeat = 0;
    my $move_pixel = 0;
    my $val = 0;
    my $x = 0;
    my $y = 0;
    my @pixels = ();

    foreach my $offset ($block_off..$end_off - 1) {
        #printf "= offset=%04X ", $offset;
        if ($move_pixel != 0) {
            #print "move_pixel set is_pixel to 1\n";
            $move_pixel = 0;
            $is_pixel = 1;
        }
        else {
            $is_pixel = 0;
        }

        if ($another_repeat != 0) {
            #print "= another_repeat set is_pixel to 1\n";
            $is_pixel = 1;
        }
        else {
            $is_pixel = 0;
        }

        #printf "-> is_pixel=%d\n", $is_pixel;

        if ($is_pixel == 0) {
            $val = unpack("\@${offset}C", $block);
            #printf "offset=%08X length=%08X\n", $offset, $end_off - $block_off;
            #printf "= ctrl=%02X\n", $val;

            $move_pixel = 0;
            $another_repeat = 0;
            $repeat_pixel = 0;

            if ($val <= 0x3F) {
                $another_repeat = 1;
                $repeat_pixel = $val;
            }
            if (0x40 <= $val && $val < 0x80) {
                $repeat_pixel = $val - 0x40;
                $another_repeat = 1;
                $is_pixel = 1;
            }
            if (0x80 <= $val && $val < 0xC0) {
                $another_repeat = $val - 0x80 + 1;
            }
            if (0xC0 <= $val) {
                $move_pixel = $val - 0xC0 + 1;
            }

            $x += $move_pixel;
            if ($x >= $width) {
                $x = 0;

                output_pixel($x, $y, \@pixels);
                @pixels = ();

                $y += 1;
                $is_pixel = 0;
            } 

            #print "= move_pixel=$move_pixel another_repeat=$another_repeat repeat_pixel=$repeat_pixel\n";
        }
        else {
            for (my $i = 0; $i <= $repeat_pixel; ++$i) {
                #if (0x40 <= $val && $val < 0x80) {
                #    $x += 1;
                #}

                $val = unpack("\@${offset}C", $block);
                push @pixels, $val;

                #printf "pos=${x},${y} idx=%02X\n", $val;

                $x += 1;
                if ($x >= $width) {
                    $x = 0;

                    output_pixel($x, $y, \@pixels);
                    @pixels = ();

                    $y += 1;
                    $is_pixel = 0;
                } 
            } # for

            $another_repeat -= 1;
        }

        last if ($y == $height);
        if ($y == $height - 1 && $x == $width - 1) {
            output_pixel($x, $y, \@pixels);
            last;
        }
    } # foreach
} # unpack_block

sub unpack_episode {
    my $fd = shift;
    my $map_off = shift;
    my $end_off = shift;
    my $block = undef;

    seek($fd, $map_off, SEEK_SET);
    read($fd, $block, $end_off - $map_off);
    my $pos = 4;
    my $block_count = unpack("\@${pos}S", $block);
    $pos += 2;

    printf "block_count=%d\n", $block_count;

    my $i = 0;
    for (; $i < $block_count - 1; ++$i) {
        my $pos2 = $pos + $i * 4;
        my $block_off = unpack("\@${pos2}I", $block);
        $pos2 += 4;
        my $next_off = unpack("\@${pos2}I", $block);
        #printf "block_off=%08X next_off=%08X size=%08X\n", $block_off, $next_off, $end_off - $map_off;
        unpack_block($i, $block, $block_off, $next_off, 24, 24);
    } # foreach

    {
        my $pos2 = $pos + $i * 4;
        my $block_off = unpack("\@${pos2}I", $block);
        $pos2 += 4;
        my $next_off = $end_off;
        #printf "block_off=%08X next_off=%08X size=%08X\n", $block_off, $next_off, $end_off - $map_off;
        unpack_block($i, $block, $block_off, $next_off, 24, 24);
    }
} # unpack_episode

my $fd = undef;

if (open($fd, "<", $ARGV[0])) {
    my $block = undef;

    read($fd, $block, DATA_OFF + INT32_SIZE * 66);
    seek($fd, 0, SEEK_END);
    my $last_end_off = tell($fd);

    for (my $i = 0; $i < 66; $i += 2) {
        printf "episode=%d\n", $i / 2;
        my $map_meta  = DATA_OFF + INT32_SIZE * $i;
        my $end_meta  = $map_meta  + INT32_SIZE;

        my $map_off = unpack("\@${map_meta}I", $block);
        my $end_off = unpack("\@${end_meta}I", $block) || $last_end_off;

        printf "map_off=%08X end_off=%08X\n", $map_off, $end_off;

        unpack_episode($fd, $map_off, $end_off);
        printf "\n";
    } # foreach

    close($fd);
}
