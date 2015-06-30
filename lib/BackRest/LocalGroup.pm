####################################################################################################################################
# LOCAL GROUP MODULE
####################################################################################################################################
package BackRest::LocalGroup;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use File::Basename qw(dirname);

use lib dirname($0) . '/../lib';
use BackRest::Config;
use BackRest::Utility;

####################################################################################################################################
# Operation constants
####################################################################################################################################
use constant OP_LOCAL_GROUP                                         => 'LocalGroup';

use constant OP_LOCAL_GROUP_BACKUP_ADD                              => OP_LOCAL_GROUP . '->backupAdd';

####################################################################################################################################
# Work Queue Constants
####################################################################################################################################
use constant WORK_CHECKSUM                                          => 'checksum';
use constant WORK_COMPRESS                                          => 'compress';
use constant WORK_DESTINATION_FILE                                  => 'destination-file';
use constant WORK_SOURCE_FILE                                       => 'source-file';
use constant WORK_TIMESTAMP                                         => 'timestamp';

use constant QUEUE_DEPTH_MAX                                        => 10;

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;              # Class name
    my $iProcessTotal = shift;      # Total local processes to spawn (if undef use optionGet())

    # Create the class hash
    my $self = {};
    bless $self, $class;

    $self->{iProcessTotal} = defined($iProcessTotal) ? $iProcessTotal : optionGet(OPTION_PROCESS_MAX);
    $self->{oWorkQueue} = {};
    $self->{oWorkList} = undef;

    # Create the process work lists
    $self->{oProcessList} = [];

    for (my $iProcessIdx = 0; $iProcessIdx < $iProcessTotal; $iProcessIdx++)
    {
        push $self->{oProcessList}, [];
    }

    return $self;
}

####################################################################################################################################
# backupAdd
####################################################################################################################################
sub backupAdd
{
    my $self = shift;
    my $strPathKey = shift;             # Path key used to balance backups among processes
    my $strSourceFile = shift;          # Source file to backup
    my $strDestinationFile = shift;     # Destination backup file
    my $bCompress = shift;              # Compress destination file
    my $strChecksum = shift;            # File checksum to be checked
    my $lTimestamp = shift;             # File timestamp
    my $lSize = shift;                  # File size used for sorting - actual size is calculated during transfer

    logDebug(OP_LOCAL_GROUP_BACKUP_ADD, DEBUG_CALL, undef, {pathKey => $strPathKey, sourceFile => $strSourceFile,
             destinationFile => $strDestinationFile, isCompressed => $bCompress, checksum => $strChecksum,
             timestamp => $lTimestamp, size => $lSize});

    # Generate key used for sorting the files before processing
    my $strFileKey = sprintf("%016d-${strSourceFile}", $lSize);

    # Store backup data in the work queue
    ${$self->{oWorkQueue}}{$strPathKey}{$strFileKey}{&WORK_SOURCE_FILE} = $strSourceFile;
    ${$self->{oWorkQueue}}{$strPathKey}{$strFileKey}{&WORK_DESTINATION_FILE} = $strDestinationFile;
    ${$self->{oWorkQueue}}{$strPathKey}{$strFileKey}{&WORK_COMPRESS} = $bCompress ? true : false;
    ${$self->{oWorkQueue}}{$strPathKey}{$strFileKey}{&WORK_CHECKSUM} = $strChecksum;
    ${$self->{oWorkQueue}}{$strPathKey}{$strFileKey}{&WORK_TIMESTAMP} = $lTimestamp;
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # If the work list has not been defined then create it
    my $oWorkList = $self->{oWorkList};

    if (!defined($oWorkList))
    {
        $oWorkList = [];

        # Loop through each path key (tablespace)
        foreach my $strPathKey (sort(keys(%{$self->{oWorkQueue}})))
        {
            my $oWorkSub = [];

            foreach my $strFileKey (sort {$b cmp $a} (keys(%{$self->{oWorkQueue}{$strPathKey}})))
            {
                &log(DEBUG, "    adding ${strFileKey}");

                push $oWorkSub, $self->{oWorkQueue}{$strPathKey}{$strFileKey};
            }

            &log(DEBUG, "pushing ${strPathKey}");
            push $oWorkList, $oWorkSub;
        }

        $self->{oWorkList} = $oWorkList;
    }

    my $iTablespaceTotal = @{$oWorkList};

    # Push work into the process queues
    for (my $iProcessIdx = 0; $iProcessIdx < $self->{iProcessTotal}; $iProcessIdx++)
    {
        my $oProcessList = ${$self->{oProcessList}}[$iProcessIdx];

        if (@{$oProcessList} < QUEUE_DEPTH_MAX && @{$$oWorkList[0]} > 0)
        {

        }
    }

    # # Make sure this is working
    # for (my $iGroupIdx = 0; $iGroupIdx < @{$oWorkList}; $iGroupIdx++)
    # {
    #     my $oSubList = $$oWorkList[$iGroupIdx];
    #
    #     &log(DEBUG, "group ${iGroupIdx}");
    #
    #     for(my $iFileIdx = 0; $iFileIdx < @{$oSubList}; $iFileIdx++)
    #     {
    #         my $oFile = $$oSubList[$iFileIdx];
    #
    #         &log(DEBUG, "    file " . $$oFile{&WORK_SOURCE_FILE});
    #     }
    # }
}

1;
