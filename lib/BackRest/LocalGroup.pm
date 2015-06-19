####################################################################################################################################
# LOCAL GROUP MODULE
####################################################################################################################################
package BackRest::LocalGroup;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use File::Basename qw(dirname);

use lib dirname($0);

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;              # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    return $self;
}

1;
