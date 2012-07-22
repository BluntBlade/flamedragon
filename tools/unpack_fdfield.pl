#!/usr/bin/env perl

use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_END);

use constant INT32_SIZE => 4;
use constant DATA_OFF => 6;

sub unpack_tiles {
    my $block = shift;
    my $offset = shift;
    my $size = shift;

    my $pos = $offset;

    my $width = unpack("\@${pos}S", $block);
    $pos += 2;
    my $height = unpack("\@${pos}S", $block);
    $pos += 2;

    printf "width=%d height=%d\n", $width, $height;
    foreach my $y (0..$height - 1) {
        foreach my $x (0..$width - 1) {
            my $tile_id = unpack("\@${pos}S", $block);
            $pos += 2;
            my $trigger_id = unpack("\@${pos}S", $block);
            $pos += 2;

            printf "pos=${x},${y} tile=%d trigger=%d\n", $tile_id, $trigger_id;
        } # foreach
    } # foreach
} # unpack_tiles

sub unpack_ctrl {
    my $block = shift;
    my $offset = shift;
    my $size = shift;

    my $pos = $offset;

    # control area
    my $map_id = unpack("\@${pos}C", $block);
    ++$pos;
    my $fighters = unpack("\@${pos}C", $block);
    ++$pos;
    my $startup_id = unpack("\@${pos}C", $block);
    ++$pos;

    printf "map=%d fighters=%d startup=%d\n", $map_id, $fighters, $startup_id;

    # event area
    foreach my $i (0..15) {
        my $turn = unpack("\@${pos}C", $block);
        ++$pos;
        my $id = unpack("\@${pos}C", $block);
        ++$pos;
        my $unknown = unpack("\@${pos}C", $block);
        ++$pos;

        printf "event=$i turn=%d id=%d unknown=%d\n", $turn, $id, $unknown;
    } # foreach

    # skip trivial info area
    $pos += 16 * 2;

    # trigger area
    foreach my $i (0..15) {
        my $type = unpack("\@${pos}C", $block);
        ++$pos;
        my $num = unpack("\@${pos}S", $block);
        $pos += 2;

        my $unit = undef;

        if ($type == 1) {
            $type = "money";
            $unit = "value";
        }
        else {
            $type = "item";
            $unit = "index";
        }

        printf "trigger=$i type=%s ${unit}=%d\n", $type, $num;
    } # foreach
} # unpack_ctrl

sub unpack_positions {
    my $block = shift;
    my $offset = shift;
    my $size = shift;

    my $pos = $offset;

    my $positions = unpack("\@${pos}S", $block);
    $pos += 2;

    printf "positions=$positions\n";

    foreach my $i (0..$positions - 1) {
        my $x = unpack("\@${pos}S", $block);
        $pos += 2;
        my $y = unpack("\@${pos}S", $block);
        $pos += 2;
        my $headpic = unpack("\@${pos}S", $block);
        $pos += 2;

        printf "pos=${x},${y} headpic=%d\n", $headpic;
    } # foreach
} # unpack_positions

sub unpack_episode {
    my $fd = shift;
    my $map_off = shift;
    my $ctrl_off = shift;
    my $pos_off = shift;
    my $end_off = shift;
    my $block = undef;

    seek($fd, $map_off, SEEK_SET);
    read($fd, $block, $end_off - $map_off);

    my $tiles_size     = $ctrl_off - $map_off;
    my $ctrl_size      = $pos_off - $ctrl_off;
    my $positions_size = $end_off - $pos_off;

    unpack_ctrl($block, $tiles_size, $ctrl_size);
    unpack_positions($block, $tiles_size + $ctrl_size, $positions_size);
    unpack_tiles($block, 0, $tiles_size);

    printf "\n";
} # unpack_episode

my $fd = undef;

if (open($fd, "<", $ARGV[0])) {
    my $block = undef;

    read($fd, $block, DATA_OFF + INT32_SIZE * 3 * 33);
    seek($fd, 0, SEEK_END);
    my $last_end_off = tell($fd);

    foreach my $i (0..32) {
        my $map_meta  = DATA_OFF + INT32_SIZE * 3 * $i;
        my $ctrl_meta = $map_meta  + INT32_SIZE;
        my $pos_meta  = $ctrl_meta + INT32_SIZE;
        my $end_meta  = $pos_meta  + INT32_SIZE;

        my $map_off = unpack("\@${map_meta}I", $block);
        my $ctrl_off = unpack("\@${ctrl_meta}I", $block);
        my $pos_off = unpack("\@${pos_meta}I", $block);
        my $end_off = unpack("\@${end_meta}I", $block) || $last_end_off;

        #printf "%04X %04X %04X %04X\n", $map_off, $ctrl_off, $pos_off, $end_off;

        unpack_episode($fd, $map_off, $ctrl_off, $pos_off, $end_off);
    } # foreach

    close($fd);
}
