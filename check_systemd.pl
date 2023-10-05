#!/usr/bin/perl -w
# check_systemd.pl
#---------------------------------------------------------------------------
#  Author(s): hbrennhaeuser
#  Created: Jan 23, 2022
#  Last modified: Oct 4, 2023
#  License: GPL v3
#  Version: 1.0.3
#
#  License information:
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Changelog: 
#    v1.0.0  - hbrennhaeuser, 04 Oct, 2023
#              Rename from check_systemctl.pl to check_systemd.pl
#              Major rewrite aiming to 
#                  ... match features and behavior of Friedrich/check_systemd v2.0.9
#                  ... be able to run on more systems without requiring installation of additional libraries
#                  ... provide better code quality
#
#---------------------------------------------------------------------------

use warnings;
use strict;

use JSON::Parse qw(parse_json);
use Getopt::Long;

our $VERSION = '1.0.3';

my $MP_OK = 0;
my $MP_WARNING = 1;
my $MP_CRITICAL = 2;
my $MP_UNKNOWN = 3;

my $ec=$MP_OK;
my $et;
my $pd;




sub print_help{
print("check_systemd.pl $VERSION

(C) hbrennhaeuser 2023
This plugin is licensed under the terms of the GNU General Public License Version 3,you will find a copy of this license in the LICENSE file included in the source package.

Nagios / Icinga compatible monitoring plugin to check systemd for failed units!

SYNTAX: check_systemd.pl [-u <UNIT> | -e <UNIT>] [-l] [-v] [-h]
            -u, --unit <UNIT>       - Specific full unit name to be checked
            -e, --exclude <REGEX>   - Exclude units using regex. May be specified multiple times. Does not apply if --unit is being used.
            -l, --legacy            - Legacy mode, enable for systemd versions without support for --output=json
            -v, --verbose           - Enable verbose output
            -h, --help              - Print this message
");
exit($MP_UNKNOWN);
}

# --

my $opt = {};
Getopt::Long::Configure(qw( gnu_getopt ignore_case_always ));
Getopt::Long::GetOptions(
    'unit|u=s'          => \$opt->{'unit'},
    'exclude|e=s@'      => \$opt->{'exclude'},
    'legacy|l'          => \$opt->{'legacy'},
    'verbose|v'         => \$opt->{'verbose'},
    'help|h'            => \$opt->{'help'},
);

print_help() if (defined($opt->{'help'}));



# ========================

sub set_ec {
    my ($ec_old, $ec_new) = @_;
    my $ec_return = $ec_old;
    $ec_return = $ec_new if ( $ec_new > $ec_old);
    return $ec_return;
}


sub check_exclude {
    my ($excludes,$unit)=@_;
    my $out = 0;

    foreach my $tmp_exclude ( @$excludes ){
        if ( $unit =~ m/$tmp_exclude/gixms ){
            $out = 1;
        }
    }
    return $out;
}


sub query_systemd_units_json {
    my $cmd="systemctl list-units --all --full --output=json --no-pager";
    my @out=`$cmd`;

    my $units = parse_json($out[0]);


    return ($units);
}



sub query_systemd_units {

    my $cmd="systemctl list-units --all --full --no-pager";
    my @out=`$cmd`;
    my @units_all;

    foreach my $line ( @out ){

        $line =~ s/[^[:ascii:]]//gxms; # Only return ascii-characters to $line
        $line =~ s/\s+/\ /gxms; # Replace multiple whitespaces with one
        $line =~ s/^\*+//gxms; # Remove leading star
        $line =~ s/^\s+//gxms; # Remove leading whitespaces

        if ( ! $line =~ m/\s*/xms ){
            my %entry;

            my ($unit, $load, $active, $sub, $desc) = ('','','','','');
            my @line_split = split(/\s+/, $line);

            $unit = $line_split[0]; shift (@line_split);
            $load = $line_split[0]; shift (@line_split);
            $active = $line_split[0]; shift (@line_split);
            $sub = $line_split[0]; shift (@line_split);
            $desc = join(' ', @line_split);

            if ( defined($unit) && defined($load) && defined($active) && defined($sub) &&
                $unit ne '' && $load =~ /\S+/ixms && $active =~ /\S+/ixms && $sub ne '' ){

                $entry{'unit'}=$unit;
                $entry{'active'}=$active;
                $entry{'sub'}=$sub;
                $entry{'description'}=$desc;
                $entry{'load'}=$load;

                #TODO: Validation

                push(@units_all, \%entry);
            }
        }
    }
    return (\@units_all);
}

# ========================



my ($units);
if ( $opt->{'legacy'} ){
    ($units) = query_systemd_units();
} else {
    ($units) = query_systemd_units_json();
}


if ($opt->{'unit'}){
    if ( my @units = grep { $_->{unit} eq $opt->{'unit'} } @$units ){
        my $unit_active = $units[0]->{active};
        $et = $opt->{'unit'}.' is '.$unit_active.'!';
        if ( $unit_active eq 'failed' ){
            $ec = set_ec($ec, $MP_CRITICAL);
        } else {
            $ec = set_ec($ec, $MP_OK);
        }
    } else {
        $ec = set_ec($ec, $MP_UNKNOWN);
        $et = $opt->{'unit'}.' could not be found!';
    }
} else {

    my $units_excluded=[];
    my $units_active = [];
    my $units_inactive = [];
    my $units_failed = [];
    my $units_unknown = [];

    foreach my $unit (@$units){

        if ( check_exclude($opt->{'exclude'},$unit->{unit}) ){
            push(@{$units_excluded}, $unit);
            next;
        }

        if ( $unit->{active} eq 'active'){
            push(@{$units_active}, $unit);
        } elsif ( $unit->{active} eq 'inactive'){
            push(@{$units_inactive}, $unit);
        } elsif ( $unit->{active} eq 'failed'){
            push(@{$units_failed}, $unit);
        } else {
            push(@{$units_unknown}, $unit);
        }
    }

    if (@$units_failed >= 1){
        $ec = set_ec($ec, $MP_CRITICAL);
    }


    $et .= @$units_failed.' failed units!';

    foreach my $unit (@$units_failed) {
        $et .= "\n".$unit->{unit}.': failed';
    }

    $pd .= " 'count_units'=".@$units;
    $pd .= " 'units_active'=".@$units_active;
    $pd .= " 'units_inactive'=".@$units_inactive;
    $pd .= " 'units_failed'=".@$units_failed;
    $pd .= " 'units_unknown'=".@$units_unknown;
    $pd .= " 'units_excluded'=".@$units_excluded;

}


if ( $ec == $MP_OK) {
    $et = 'SYSTEMD OK: '.$et;
} elsif ( $ec == $MP_WARNING) {
    $et = 'SYSTEMD WARNING: '.$et;
} elsif ( $ec == $MP_CRITICAL) {
    $et = 'SYSTEMD CRITICAL: '.$et;
} else {
    $et = 'SYSTEMD UNKNOWN: '.$et;
}



$et = $et.' |'.$pd if ($pd);

print($et."\n");
exit($ec);
