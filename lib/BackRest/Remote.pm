####################################################################################################################################
# REMOTE MODULE
####################################################################################################################################
package BackRest::Remote;
use parent 'BackRest::Protocol';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Compress::Raw::Zlib qw(WANT_GZIP Z_OK Z_BUF_ERROR Z_STREAM_END);
use File::Basename qw(dirname);

use IO::String qw();
use Net::OpenSSH qw();
use POSIX qw(:sys_wait_h);
use Scalar::Util qw(blessed);

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
use constant OP_REMOTE                                            => 'Remote';

use constant OP_REMOTE_NEW                                        => OP_REMOTE . "->new";

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant
{
    OP_NOOP        => 'noop',
    OP_EXIT        => 'exit'
};

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name
    my $strHost = shift;                # Host to connect to for remote (optional as this can also be used on the remote)
    my $strUser = shift;                # User to connect to for remote (must be set if strHost is set)
    my $strCommand = shift;             # Command to execute on remote ('remote' if this is the remote)
    my $iBlockSize = shift;             # Buffer size
    my $iCompressLevel = shift;         # Set compression level
    my $iCompressLevelNetwork = shift;  # Set compression level for network only compression

    # Debug
    logDebug(OP_REMOTE_NEW, DEBUG_CALL, undef,
             {host => $strHost, user => $strUser, command => $strCommand},
             defined($strHost) ? DEBUG : TRACE);

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Create the greeting that will be used to check versions with the remote
    $self->{strGreeting} = 'PG_BACKREST_REMOTE ' . version_get();

    # Set default block size
    $self->{iBlockSize} = $iBlockSize;

    # Set compress levels
    $self->{iCompressLevel} = $iCompressLevel;
    $self->{iCompressLevelNetwork} = $iCompressLevelNetwork;

    # If host is defined then make a connnection
    if (defined($strHost))
    {
        # User must be defined
        if (!defined($strUser))
        {
            confess &log(ASSERT, 'strUser must be defined');
        }

        # Command must be defined
        if (!defined($strCommand))
        {
            confess &log(ASSERT, 'strCommand must be defined');
        }

        $self->{strHost} = $strHost;
        $self->{strUser} = $strUser;
        $self->{strCommand} = $strCommand . ' remote';

        # Set SSH Options
        my $strOptionSSHRequestTTY = 'RequestTTY=yes';
        my $strOptionSSHCompression = 'Compression=no';

        &log(TRACE, 'connecting to remote ssh host ' . $self->{strHost});

        # Make SSH connection
        $self->{oSSH} = Net::OpenSSH->new($self->{strHost}, timeout => 600, user => $self->{strUser},
                                          master_opts => [-o => $strOptionSSHCompression, -o => $strOptionSSHRequestTTY]);

        $self->{oSSH}->error and confess &log(ERROR, "unable to connect to $self->{strHost}: " . $self->{oSSH}->error,
                                              ERROR_HOST_CONNECT);
        &log(TRACE, 'connected to remote ssh host ' . $self->{strHost});

        # Execute remote command
        ($self->{hIn}, $self->{hOut}, $self->{hErr}, $self->{pId}) = $self->{oSSH}->open3($self->{strCommand});

        $self->greeting_read();
    }
    elsif (defined($strCommand) && $strCommand eq 'remote')
    {
        # Write the greeting so master process knows who we are
        $self->greeting_write();
    }

    # Check block size
    if (!defined($self->{iBlockSize}))
    {
        confess &log(ASSERT, 'iBlockSize must be set');
    }

    # Check compress levels
    if (!defined($self->{iCompressLevel}))
    {
        confess &log(ASSERT, 'iCompressLevel must be set');
    }

    if (!defined($self->{iCompressLevelNetwork}))
    {
        confess &log(ASSERT, 'iCompressLevelNetwork must be set');
    }

    return $self;
}

####################################################################################################################################
# paramGet
#
# Helper function that returns the param or an error if required and it does not exist.
####################################################################################################################################
sub paramGet
{
    my $oParamHashRef = shift;
    my $strParam = shift;
    my $bRequired = shift;

    my $strValue = ${$oParamHashRef}{$strParam};

    if (!defined($strValue) && (!defined($bRequired) || $bRequired))
    {
        confess "${strParam} must be defined";
    }

    return $strValue;
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Turn all logging off
    log_level_set(OFF, OFF);

    # Create the remote object
    my $oProtocol = new BackRest::Protocol
    (
        undef,      # Host
        undef,      # User
        'remote',   # Command
        optionGet(OPTION_BUFFER_SIZE),
        optionGet(OPTION_COMPRESS_LEVEL),
        optionGet(OPTION_COMPRESS_LEVEL_NETWORK)
    );

    # Create the file object
    my $oFile = new BackRest::File
    (
        optionGet(OPTION_STANZA, false),
        optionGet(OPTION_REPO_REMOTE_PATH, false),
        undef,
        $oProtocol,
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

        $strCommand = $oProtocol->command_read(\%oParamHash);

        eval
        {
            # Copy file
            if ($strCommand eq OP_FILE_COPY ||
                $strCommand eq OP_FILE_COPY_IN ||
                $strCommand eq OP_FILE_COPY_OUT)
            {
                my $bResult;
                my $strChecksum;
                my $iFileSize;

                # Copy a file locally
                if ($strCommand eq OP_FILE_COPY)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PATH_ABSOLUTE, paramGet(\%oParamHash, 'source_file'),
                                     PATH_ABSOLUTE, paramGet(\%oParamHash, 'destination_file'),
                                     paramGet(\%oParamHash, 'source_compressed'),
                                     paramGet(\%oParamHash, 'destination_compress'),
                                     paramGet(\%oParamHash, 'ignore_missing_source', false),
                                     undef,
                                     paramGet(\%oParamHash, 'mode', false),
                                     paramGet(\%oParamHash, 'destination_path_create') ? 'Y' : 'N',
                                     paramGet(\%oParamHash, 'user', false),
                                     paramGet(\%oParamHash, 'group', false),
                                     paramGet(\%oParamHash, 'append_checksum', false));
                }
                # Copy a file from STDIN
                elsif ($strCommand eq OP_FILE_COPY_IN)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PIPE_STDIN, undef,
                                     PATH_ABSOLUTE, paramGet(\%oParamHash, 'destination_file'),
                                     paramGet(\%oParamHash, 'source_compressed'),
                                     paramGet(\%oParamHash, 'destination_compress'),
                                     undef, undef,
                                     paramGet(\%oParamHash, 'mode', false),
                                     paramGet(\%oParamHash, 'destination_path_create'),
                                     paramGet(\%oParamHash, 'user', false),
                                     paramGet(\%oParamHash, 'group', false),
                                     paramGet(\%oParamHash, 'append_checksum', false));
                }
                # Copy a file to STDOUT
                elsif ($strCommand eq OP_FILE_COPY_OUT)
                {
                    ($bResult, $strChecksum, $iFileSize) =
                        $oFile->copy(PATH_ABSOLUTE, paramGet(\%oParamHash, 'source_file'),
                                     PIPE_STDOUT, undef,
                                     paramGet(\%oParamHash, 'source_compressed'),
                                     paramGet(\%oParamHash, 'destination_compress'));
                }

                $oProtocol->output_write(($bResult ? 'Y' : 'N') . " " . (defined($strChecksum) ? $strChecksum : '?') . " " .
                                       (defined($iFileSize) ? $iFileSize : '?'));
            }
            # List files in a path
            elsif ($strCommand eq OP_FILE_LIST)
            {
                my $strOutput;

                foreach my $strFile ($oFile->list(PATH_ABSOLUTE, paramGet(\%oParamHash, 'path'),
                                                  paramGet(\%oParamHash, 'expression', false),
                                                  paramGet(\%oParamHash, 'sort_order'),
                                                  paramGet(\%oParamHash, 'ignore_missing')))
                {
                    if (defined($strOutput))
                    {
                        $strOutput .= "\n";
                    }

                    $strOutput .= $strFile;
                }

                $oProtocol->output_write($strOutput);
            }
            # Create a path
            elsif ($strCommand eq OP_FILE_PATH_CREATE)
            {
                $oFile->path_create(PATH_ABSOLUTE, paramGet(\%oParamHash, 'path'), paramGet(\%oParamHash, 'mode', false));
                $oProtocol->output_write();
            }
            # Check if a file/path exists
            elsif ($strCommand eq OP_FILE_EXISTS)
            {
                $oProtocol->output_write($oFile->exists(PATH_ABSOLUTE, paramGet(\%oParamHash, 'path')) ? 'Y' : 'N');
            }
            # Wait
            elsif ($strCommand eq OP_FILE_WAIT)
            {
                $oProtocol->output_write($oFile->wait(PATH_ABSOLUTE));
            }
            # Generate a manifest
            elsif ($strCommand eq OP_FILE_MANIFEST)
            {
                my %oManifestHash;

                $oFile->manifest(PATH_ABSOLUTE, paramGet(\%oParamHash, 'path'), \%oManifestHash);

                my $strOutput = "name\ttype\tuser\tgroup\tmode\tmodification_time\tinode\tsize\tlink_destination";

                foreach my $strName (sort(keys $oManifestHash{name}))
                {
                    $strOutput .= "\n${strName}\t" .
                        $oManifestHash{name}{"${strName}"}{type} . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{user}) ? $oManifestHash{name}{"${strName}"}{user} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{group}) ? $oManifestHash{name}{"${strName}"}{group} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{mode}) ? $oManifestHash{name}{"${strName}"}{mode} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{modification_time}) ?
                            $oManifestHash{name}{"${strName}"}{modification_time} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{inode}) ? $oManifestHash{name}{"${strName}"}{inode} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{size}) ? $oManifestHash{name}{"${strName}"}{size} : "") . "\t" .
                        (defined($oManifestHash{name}{"${strName}"}{link_destination}) ?
                            $oManifestHash{name}{"${strName}"}{link_destination} : "");
                }

                $oProtocol->output_write($strOutput);
            }
            # Archive push checks
            elsif ($strCommand eq OP_ARCHIVE_PUSH_CHECK)
            {
                my ($strArchiveId, $strChecksum) = $oArchive->pushCheck($oFile,
                                                                        paramGet(\%oParamHash, 'wal-segment'),
                                                                        undef,
                                                                        paramGet(\%oParamHash, 'db-version'),
                                                                        paramGet(\%oParamHash, 'db-sys-id'));

                $oProtocol->output_write("${strArchiveId}\t" . (defined($strChecksum) ? $strChecksum : 'Y'));
            }
            elsif ($strCommand eq OP_ARCHIVE_GET_CHECK)
            {
                $oProtocol->output_write($oArchive->getCheck($oFile));
            }
            # Info list stanza
            elsif ($strCommand eq OP_INFO_LIST_STANZA)
            {
                $oProtocol->output_write(
                    $oJSON->encode(
                        $oInfo->listStanza($oFile,
                                       paramGet(\%oParamHash, 'stanza', false))));
            }
            elsif ($strCommand eq OP_DB_INFO)
            {
                my ($strDbVersion, $iControlVersion, $iCatalogVersion, $ullDbSysId) =
                    $oDb->info($oFile, paramGet(\%oParamHash, 'db-path'));

                $oProtocol->output_write("${strDbVersion}\t${iControlVersion}\t${iCatalogVersion}\t${ullDbSysId}");
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
            $oProtocol->error_write($@);
        }
    }
}

1;
