####################################################################################################################################
# LOCAL MODULE
####################################################################################################################################
package BackRest::Local;
use parent 'BackRest::Protocol';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Archive;
use BackRest::Config;
use BackRest::Db;
use BackRest::Exception;
use BackRest::File;
use BackRest::Info;
use BackRest::Protocol;
use BackRest::Utility;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_LOCAL                                               => 'Local';

use constant OP_LOCAL_NEW                                           => OP_LOCAL . "->new";

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name
    my $strCommand = shift;             # Command to execute
    my $iBlockSize = shift;             # Buffer size
    my $iCompressLevel = shift;         # Set compression level
    my $iCompressLevelNetwork = shift;  # Set compression level for network only compression

    # Debug
    logDebug(OP_LOCAL_NEW, DEBUG_CALL, undef, {command => $strCommand});

    # Init object and store variables
    my $self = $class->SUPER::new(CMD_LOCAL, !defined($strCommand), $strCommand, $iBlockSize, $iCompressLevel,
                                  $iCompressLevelNetwork);

    return $self;
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Create the file object
    my $oFile = new BackRest::File
    (
        optionGet(OPTION_STANZA, false),
        optionGet(OPTION_REPO_REMOTE_PATH, false),
        undef,
        $self,
    );

    # Create objects
    my $oArchive = new BackRest::Archive();
    my $oInfo = new BackRest::Info();
    my $oJSON = JSON::PP->new();
    my $oDb = new BackRest::Db(false);

    # Command string
    my $strCommand = OP_NOOP;

    # Loop until the exit command is received
    while ($strCommand ne OP_EXIT)
    {
        my %oParamHash;

        $strCommand = $self->command_read(\%oParamHash);

        eval
        {
            # Backup file
            if ($strCommand eq OP_DB_INFO)
            {
                # my ($strDbVersion, $iControlVersion, $iCatalogVersion, $ullDbSysId) =
                #     $oDb->info($oFile, $self->paramGet(\%oParamHash, 'db-path'));
                #
                # $self->output_write("${strDbVersion}\t${iControlVersion}\t${iCatalogVersion}\t${ullDbSysId}");
            }
            # Continue if noop or exit
            elsif ($strCommand ne OP_NOOP && $strCommand ne OP_EXIT)
            {
                confess "invalid command: ${strCommand}";
            }
        };

        # Process errors
        if ($@)
        {
            $self->error_write($@);
        }
    }
}

1;
