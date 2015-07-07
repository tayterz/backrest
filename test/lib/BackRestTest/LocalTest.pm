#!/usr/bin/perl
####################################################################################################################################
# LocalTest.pm - Unit Tests for BackRest::Local
####################################################################################################################################
package BackRestTest::LocalTest;

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Config;
use BackRest::LocalGroup;
use BackRest::Utility;

use BackRestTest::CommonTest;

####################################################################################################################################
# BackRestTestLocal_Test
####################################################################################################################################
our @EXPORT = qw(BackRestTestLocal_Test);

sub BackRestTestLocal_Test
{
    my $strTest = shift;

    # Setup test variables
    my $iRun;
    my $bCreate;
    my $strStanza = 'main';

    my $strModule = 'local';
    my $strThisTest;

    # Print test banner
    &log(INFO, uc($strModule) . ' MODULE ******************************************************************');
    BackRestTestCommon_Drop();

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test backup
    #-------------------------------------------------------------------------------------------------------------------------------
    $strThisTest = 'backup';

    if ($strTest eq 'all' || $strTest eq $strThisTest)
    {
        $iRun = 0;

        my $strCommand = BackRestTestCommon_CommandMainAbsGet() .
                         ' --stanza=' . BackRestTestCommon_StanzaGet() .
                         ' ' . CMD_LOCAL;

        my $oGroup = new BackRest::LocalGroup
        (
            $strCommand,                            # Local command to run
            2,                                      # Number of local processes to run
            OPTION_DEFAULT_BUFFER_SIZE,             # Buffer size
            OPTION_DEFAULT_COMPRESS_LEVEL,          # Compress level
            OPTION_DEFAULT_COMPRESS_LEVEL_NETWORK   # Compress network level
        );

        $oGroup->backupAdd('base', 'source1', 'dest', true, undef, 1234, 1111);
        $oGroup->backupAdd('base', 'source2', 'dest', true, undef, 1234, 5555);
        $oGroup->backupAdd('tablespace1', 'source3', 'dest', true, undef, 1234, 2222);

        $oGroup->process();

        &log(INFO, "Test ${strThisTest}\n");
    }
}

1;
