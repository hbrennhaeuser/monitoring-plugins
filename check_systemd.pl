#!/usr/bin/perl -w
# check_systemd.pl
#---------------------------------------------------------------------------
#  Author(s): hbrennhaeuser
#  Created: Jan 23, 2022
#  Last modified: Feb 03, 2025
#  License: GPL v3
#  Version: 1.2.0
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
#  Changelog:
#    v1.2.0 - hbrennhaeuser, Feb 03, 2025
#             Add optional check of ActiveEnterTimestamp
#    v1.1.0 - hbrennhaeuser, Oct 10, 2023
#             Remove support for --output=json (remove JSON::Parse requirement)
#    v1.0.4 - hbrennhaeuser, Oct 04, 2023
#             Minor Changes
#    v1.0.0 - hbrennhaeuser, 04 Oct, 2023
#             Rename from check_systemctl.pl to check_systemd.pl
#             Major rewrite aiming to 
#                 ... match features and behavior of Friedrich/check_systemd v2.0.9
#                 ... be able to run on more systems without requiring installation of additional libraries
#                 ... provide better code quality
#
#---------------------------------------------------------------------------

use warnings;
use strict;
use 5.010;

# This plugin is intentionally using as few libraries as possible.
use Getopt::Long;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Time::Piece;

our $VERSION = '1.2.0';
our $SHORTNAME = "SYSTEMD";
our %MP_CODES = (
    OK       => 0,
    WARNING  => 1,
    CRITICAL => 2,
    UNKNOWN  => 3,
);
our %MP_TEXTS = reverse %MP_CODES;

my $ec = $MP_CODES{OK};
my $et;
my $pd;




sub print_help {
    print("check_systemd.pl $VERSION

(C) hbrennhaeuser 2025
This plugin is licensed under the terms of the GNU General Public License Version 3,you will find a copy of this license in the LICENSE file included in the source package.

Nagios / Icinga compatible monitoring plugin to check systemd for failed units!

SYNTAX: check_systemd.pl [-u <UNIT> [-w <sec>] [-c <sec>] | -e <UNIT>] [-l] [-v] [-h]
            -u, --unit <UNIT>       - Specific full unit name to be checked
            -e, --exclude <REGEX>   - Exclude units using regex. May be specified multiple times. Does not apply if --unit is being used.
            -l, --legacy            - [Unused] This argument does nothing. It remains for backwards-compatibility-reasons
            -w, --warning <sec>     - Check seconds since units ActiveEnterTimestamp, only available when --unit is specified.
            -c, --critical <sec>    - Check seconds since units ActiveEnterTimestamp, only available when --unit is specified.
            -v, --verbose           - Enable verbose output
            -h, --help              - Print this message
");
    exit($MP_CODES{UNKNOWN});
}

# --

my $opt = {};
Getopt::Long::Configure(qw( gnu_getopt ignore_case_always ));
Getopt::Long::GetOptions(
    'unit|u=s'          => \$opt->{'unit'},
    'exclude|e=s@'      => \$opt->{'exclude'},
    'legacy|l'          => \$opt->{'legacy'},
    'warning|w'          => \$opt->{'warning'},
    'critical|c'          => \$opt->{'critical'},
    'verbose|v'         => \$opt->{'verbose'},
    'help|h'            => \$opt->{'help'},
);

print_help() if (defined($opt->{'help'}));

# ========================

sub set_ec {
    my ($ec_new) = @_;
    $ec = $ec_new if ($ec_new > $ec);
}

sub get_new_ec {
    my ($ec_old, $ec_new) = @_;
    return $ec_new if ($ec_new > $ec_old);
    return $ec_old;
}

sub check_exclude {
    my ($excludes, $unit) = @_;
    my $out = 0;

    foreach my $tmp_exclude (@$excludes) {
        if ($unit =~ m/$tmp_exclude/gixms) {
            $out = 1;
        }
    }
    return $out;
}

sub get_systemd_units {
    my $cmd = "systemctl list-units --all --full --no-pager";
    my @out = `$cmd`;
    my @units_all;

    foreach my $line (@out) {
        $line =~ s/[^[:ascii:]]//gxms; # Only return ascii-characters to $line
        $line =~ s/\s+/\ /gxms; # Replace multiple whitespaces with one
        $line =~ s/^\*+//gxms; # Remove leading star
        $line =~ s/^\s+//gxms; # Remove leading whitespaces

        if (! $line =~ m/\s*/xms) {
            my %entry;

            my ($unit, $load, $active, $sub, $desc) = ('','','','','');
            my @line_split = split(/\s+/, $line);

            $unit = $line_split[0]; shift (@line_split);
            $load = $line_split[0]; shift (@line_split);
            $active = $line_split[0]; shift (@line_split);
            $sub = $line_split[0]; shift (@line_split);
            $desc = join(' ', @line_split);

            if (defined($unit) && defined($load) && defined($active) && defined($sub) &&
                $unit ne '' && $load =~ /\S+/ixms && $active =~ /\S+/ixms && $sub ne '') {

                $entry{'unit'} = $unit;
                $entry{'active'} = $active;
                $entry{'sub'} = $sub;
                $entry{'description'} = $desc;
                $entry{'load'} = $load;

                #TODO: Validation

                push(@units_all, \%entry);
            }
        }
    }
    return (\@units_all);
}

sub get_systemd_unit_parameters {
    my ($unit_name) = @_;
    my $cmd = "systemctl show $unit_name --property=ActiveState,ActiveEnterTimestamp,ActiveEnterTimestampMonotonic";
    my @out = `$cmd`;
    my %unit_params;

    foreach my $line (@out) {
        $line =~ s/[^[:ascii:]]//gxms; # Only return ascii-characters to $line
        $line =~ s/\s+/\ /gxms; # Replace multiple whitespaces with one
        $line =~ s/^\s+//gxms; # Remove leading whitespaces

        if ($line =~ m/^(\S+)=(.+)/) {
            $unit_params{$1} = $2;
        }
    }
    return \%unit_params;
}

sub plugin_die {
    my ($et) = @_;
    plugin_exit($MP_CODES{UNKNOWN}, $et);
}

sub plugin_exit {
    my ($ec, $et, $pd) = @_;
    $ec = $MP_CODES{UNKNOWN} unless defined $MP_CODES{$ec};

    print("$SHORTNAME $MP_TEXTS{$ec}: ");
    print($et);
    print("\n|$pd") if($pd);
    print("\n");
    exit $ec;
}

# ========================

my ($units) = get_systemd_units();

if ($opt->{'unit'}) {
    if (my @units = grep { $_->{unit} eq $opt->{'unit'} } @$units) {
        my $unit_active_state = $units[0]->{active};
        $et = $opt->{'unit'}.' is '.$unit_active_state.'!';
        if ($unit_active_state eq 'failed') {
            set_ec($MP_CODES{CRITICAL});
        }

        if ($unit_active_state eq 'active' && (defined($opt->{'warning'}) || defined($opt->{'critical'}))) {
            my $unit_params = get_systemd_unit_parameters($opt->{'unit'});
            my $active_enter_timestamp = $unit_params->{'ActiveEnterTimestampMonotonic'};
            my $ec_tmp = $MP_CODES{OK};


            my $time_since_boot = clock_gettime(CLOCK_MONOTONIC);
            my $activeTime = ($time_since_boot * 1_000_000 - $active_enter_timestamp) / 1_000_000;
            $activeTime = int($activeTime);

            my $activeTime_pretty = Time::Piece->new($activeTime)->strftime('%Hh%Mm%Ss');
            
            if (defined($opt->{'critical'}) && $opt->{'critical'} > $activeTime){
                set_ec($MP_CODES{CRITICAL});
                $ec_tmp = get_new_ec($ec_tmp, $MP_CODES{CRITICAL});
            }
            if (defined($opt->{'warning'}) && $opt->{'warning'} > $activeTime){
                set_ec($MP_CODES{WARNING});
                $ec_tmp = get_new_ec($ec_tmp, $MP_CODES{WARNING});
            }
            $et .= " ActiveEnterTime $MP_TEXTS{$ec_tmp}, ${activeTime_pretty} ago.";
            $pd .= " 'activeTime'=${activeTime}s;;;0;";
        }

    } else {
        set_ec($MP_CODES{UNKNOWN});
        $et = $opt->{'unit'}.' could not be found!';
    }
} else {
    my $units_excluded = [];
    my $units_active = [];
    my $units_inactive = [];
    my $units_failed = [];
    my $units_unknown = [];

    foreach my $unit (@$units) {
        if (check_exclude($opt->{'exclude'}, $unit->{unit})) {
            push(@{$units_excluded}, $unit);
            next;
        }

        if ($unit->{active} eq 'active') {
            push(@{$units_active}, $unit);
        } elsif ($unit->{active} eq 'inactive') {
            push(@{$units_inactive}, $unit);
        } elsif ($unit->{active} eq 'failed') {
            push(@{$units_failed}, $unit);
        } else {
            push(@{$units_unknown}, $unit);
        }
    }

    if (@$units_failed >= 1) {
        set_ec($MP_CODES{CRITICAL});
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

if ($ec == $MP_CODES{OK}) {
    $et = 'SYSTEMD OK: '.$et;
} elsif ($ec == $MP_CODES{WARNING}) {
    $et = 'SYSTEMD WARNING: '.$et;
} elsif ($ec == $MP_CODES{CRITICAL}) {
    $et = 'SYSTEMD CRITICAL: '.$et;
} else {
    $et = 'SYSTEMD UNKNOWN: '.$et;
}

$et = $et.' |'.$pd if ($pd);

print($et."\n");
exit($ec);
