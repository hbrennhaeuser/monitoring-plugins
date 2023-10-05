#!/usr/bin/perl -w
# check_mount.pl
#---------------------------------------------------------------------------
#  Author(s): hbrennhaeuser
#  Created: Sep 15, 2023
#  Last modified: Sep 15, 2023
#  License: GPL v3
#  Version: 1.0.1
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
#    v1.0.1 - hbrennhaeuser, Sep 15, 2023
#             Minor Changes
#    v1.0.0 - hbrennhaeuser, Sep 15, 2023
#             Initial commit
#---------------------------------------------------------------------------

use warnings;
use strict;
use Getopt::Long;
# This plugin is intentionally using as few libraries as possible.


our $VERSION = '1.0.1';


BEGIN{
    use warnings;
    use strict;
    package Check_mount::Mountpoint;
    sub new {
        my $class = shift;
        my $self = {
            'mountline' => shift,
            'os' => shift,
        };

        bless $self, $class; 

        $self->{'mountline'} = $self->trim_whitespaces($self->{'mountline'});

        if ( $self->{'os'} eq 'linux' ){
            die('invalid mount output') if ( ! $self->validate_mountline_linux() );
            $self->parse_mountline_linux();
        } elsif ( $self->{'os'} eq 'bsd' ){
            die('BSD is not supported yet!');
            die('invalid mount output') if ( ! $self->validate_mountline_bsd() );
            $self->parse_mountline_bsd();
        } else {
            die('Unsupported/unknown os '.$self->{'os'})
        }

        return $self;
    }

    sub trim_whitespaces {
        my ( $self, $string ) = @_;

        $string =~ s/^\s*//msx;
        $string =~ s/\s*$//msx;

        return $string;

    }

    sub validate_mountline_linux {
        my ( $self ) =@_;
        my $status = 0;

        $status = 1 if ( $self->{'mountline'} =~ m/^.*\son\s.*\stype\s.*\s\(.*\)$/ixms);

        return $status;
    }

    sub parse_mountline_linux {
        my ( $self ) = @_;

        if ( $self->{'mountline'} =~ qr/^(.+)\son\s/ixms ){
            $self->{'dev'}= $1;
        } else {
            die('An error occured parsing dev from mountline! mountline: '.$self->{'mountline'});
        }

        if ( $self->{'mountline'} =~ qr/^(?:.*\son\s)(.+)(?:\stype)/ixms ){
            $self->{'mountpoint'}= $1;
        } else {
            die('An error occured parsing mountpoint from mountline! mountline: '.$self->{'mountline'});
        }

        if ( $self->{'mountline'} =~ qr/^(?:.*\stype\s)(\S+)(?:\s\()/ixms ){
            $self->{'fstype'}= $1;
        }else {
            die('An error occured parsing fstype from mountline! mountline: '.$self->{'mountline'});
        }

        if ( $self->{'mountline'} =~ qr/^(?:.*\stype\s)(?:\S+\s\()(.+)(?:\))$/ixms ){
            $self->{'params'}= $1;
        } else {
            die('An error occured parsing params from mountline! mountline: '.$self->{'mountline'});
        }

        return 1;
    }

    sub validate_mountline_bsd {
        my ( $self ) = @_;
        die('BSD is not supported yet!');
    }

    sub parse_mountline_bsd {
        my ( $self ) = @_;
        die('BSD is not supported yet!');
    }

    sub check_dev {
        my ( $self, $path ) = @_;
        my $status = 0;
        if ( $self->{'dev'} eq $path ){
            $status = 1;
        }
        return $status
    }

    sub check_fstype {
        my ( $self, $expected ) = @_;
        my $status = 0;
        if ( $self->{'fstype'} eq $expected ){
            $status = 1;
        }
        return $status;
    }

    sub check_params {
        my ( $self, $params, $mode ) = @_;
        # Modes:
        #   1: Expect the @$params to 100% match
        #   2: Expect all the defined params in @$params to be there, the rest is ignored
        #   3: Blacklist, check if none of the defined params are there
        my $status = 0;
        my $params_array = split( /,/ , $self->{'params'});
        die('param-checking is not implemented yet!');
        return $status;
    }

    sub check_mountpoint {
        my ( $self, $path ) = @_;
        my $status = 0;
        if ( $self->{'mountpoint'} eq $path ){
            $status = 1;
        }
        return $status;
    }

}

#===========================================================================

my ($MP_OK, $MP_WARNING, $MP_CRITICAL, $MP_UNKNOWN) = (0,1,2,3);
my $ec = $MP_OK;
my $et = '';

my $os = 'linux';

# --

sub set_ec{
    my ($ec_current, $ec_new) = @_;
    my $ec_return = $ec_current;
    $ec_return = $ec_new if ($ec_new > $ec_current);
    return $ec_return;
}

sub print_help{
print("check_mount.pl $VERSION

This plugin is licensed under the terms of the GNU General Public License Version 3,you will find a copy of this license in the LICENSE file included in the source package.

check_mount.pl lets you check a mountpoint by specifying a mountpoint, a mounted source or both. Additionally you can check the used filesystem.
The plugin evaluates the output of the 'mount'-command. It is currently only compatible with the linux-variant (util-linux), support for bsd-variants still under development.

SYNTAX: check_mount.sh < -s SOURCE | -m MOUNTPOINT > [-f FileSystem]
            -m <MOUNTPOINT>    - Mountpoint (e.g. /mnt/datashare)
            -s <SOURCE>        - Mounted Source (e.g. /dev/sdb or //192.168.163.25/share)
            -f <FileSystem>    - [optional] Filesystem (e.g. ext4, nfs, cifs, ...)
            --bsd              - [optional] Evaluate bsd-mount instead of linux (default) [Not implemented yet] 
            Either -m or -s has to be given. Both can be specified simultaneously. -f is optional.
");
exit($MP_UNKNOWN);
}

# --

Getopt::Long::Configure(qw( gnu_getopt ignore_case_always ));
Getopt::Long::GetOptions(
    'source|s=s'        => \my $opt_source,
    'mountpoint|m=s'    => \my $opt_mountpoint,
    'fs|f=s'            => \my $opt_filesystem,
    'bsd'               => \my $opt_bsd,
    'help|h'            => \my $opt_help,
);

print_help() if (defined($opt_help));

if ( !defined($opt_source) && !defined($opt_mountpoint)){
    print("Please specify either mountpoint or source to check!\n"); exit($MP_UNKNOWN);
}

if ( defined($opt_bsd) ){
    $os = 'bsd';
}

# --

my @mount_output = `mount`;

my @mounts=();
foreach my $line (@mount_output){
    my $obj =  Check_mount::Mountpoint->new($line,$os);

    if ( defined($opt_mountpoint) && defined($opt_source)){
        if ($obj->check_mountpoint($opt_mountpoint) && $obj->check_dev($opt_source)){
            push(@mounts,$obj);
        }
    } elsif (defined($opt_mountpoint) && !defined($opt_source)) {
        if ($obj->check_mountpoint($opt_mountpoint)){
            push(@mounts,$obj);
        }
    } elsif (!defined($opt_mountpoint) && defined($opt_source)) {
        if ($obj->check_dev($opt_source)){
            push(@mounts,$obj);

        }
    }
}

if ( @mounts == 1 ){
    $et.=' is mounted';
} elsif ( @mounts == 0 ){
    $et.=' is not mounted';
    $ec=set_ec($ec,$MP_CRITICAL)
} elsif ( @mounts > 1 ){
    $et.=' is mounted '.(@mounts).' times';
    $ec=set_ec($ec,$MP_WARNING);
}

if ( defined($opt_mountpoint) && defined($opt_source)){
    $et=$opt_source.$et.' on '.$opt_mountpoint;
} elsif (defined($opt_mountpoint) && !defined($opt_source)) {
    $et=$opt_mountpoint.$et;
} elsif (!defined($opt_mountpoint) && defined($opt_source)) {
    $et=$opt_source.$et;
}



if ( @mounts == 1 && defined($opt_filesystem)){
    if ($mounts[0]->check_fstype($opt_filesystem)){
        $et=$et." as $opt_filesystem";
    } else {
        $et=$et.' as '.$mounts[0]->{'fstype'}." (not $opt_filesystem)";
        $ec=set_ec($ec,$MP_CRITICAL);
    }
}


if (@mounts >=1 ){
    foreach my $mountpoint (@mounts){
        $et.="\n* ".$mountpoint->{'dev'}.' on '.$mountpoint->{'mountpoint'}.' as '.$mountpoint->{'fstype'};
    }
}



if ( $ec eq $MP_OK ){
    $et = 'OK: '.$et;
} elsif ( $ec eq $MP_WARNING ){
    $et = 'WARNING: '.$et;
} elsif ( $ec eq $MP_CRITICAL ){
    $et = 'CRITICAL: '.$et;
} else {
    $et = 'UNKNOWN: '.$et;
}

print($et."\n");
exit($ec);