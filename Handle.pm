package DBIx::BLOB::Handle; 

use base qw( IO::Handle IO::Seekable );
use strict;
use vars qw( $VERSION );
use warnings;
use Symbol;
use DBI;

$VERSION = '0.1';

sub import {
    my $class = shift;
    if( grep { $_ eq ':INTO_STATEMENT' } @_ ){
        # Danger! Pretend the DBI statement class can provide blobs as handles
        no warnings;
        *DBI::st::blob_as_handle = sub {
            return "$class"->new(@_);
        };
    }
}

# required is the DBI statement
# optional is the 0 based column index that contains the blob (default = 0)
# optional is the blocksize to be read from the database (default = 4096)
sub new {
	my($self, $sth, $field, $blocksize) = @_;
    $self = ref $self || $self;
    my $s = Symbol::gensym;
    tie $$s,$self,$sth,$field,$blocksize;
    return bless $s, $self;
}

sub TIEHANDLE {
    my $class = shift;
    return bless {sth       => shift
                 ,field     => shift || 0
                 ,blocksize => shift || 4096
                 ,pos => 0
                 },$class;
}

sub READLINE {
    my $self = shift;
    my($len,$buf) = (0,'');
    my $sth = $self->{sth};
    unless(wantarray){
        $sth->blob_read($self->{field}, $self->{pos}, $self->{blocksize},\$buf);
        $len = length $buf;
        return undef unless $len;
        $self->{pos} += $len;
        return $buf;
    }
    my @frags;
    while(1){
        $sth->blob_read($self->{field}, $self->{pos}, $self->{blocksize},\$buf);
        $len = length $buf;
        last unless $len;
        $self->{pos} += $len;
        push @frags, $buf;
    }
    return @frags;
}

sub TELL{
    return $_[0]->{pos};
}

sub EOF{
    my $self = shift;
    my $buf = '';
    $self->{sth}->blob_read($self->{field}, $self->{pos}, 1,\$buf);
    return ! length $buf;
}

1;

__END__

=head1 NAME

DBIx::BLOB::Handle - Read Database Large Object Binaries from file handles

=head1 SYNOPSIS

use DBI;

use DBIx::BLOB::Handle;

# use DBIx::BLOB::Handle qw( :INTO_STATEMENT );

$dbh = DBI->connect('DBI:Oracle:ORCL','scott','tiger',
                    {RaiseError => 1, PrintError => 0 }
				   )
                   
or die 'Could not connect to database:' , DBI->errstr;

$dbh->{LongTruncOk} = 1; # very important!

$sql = 'select mylob from mytable where id = 1';

$sth = $dbh->prepare($sql);

$sth->execute;

$sth->fetch;

$fh = DBIx::BLOB::Handle->new($sth,0,4096);

...

print while <$fh>;

# print $fh->getlines;

print STDERR 'Size of LOB was ' . $fh->tell . " bytes\n";

...

# or if we used the dangerous :INTO_STATEMENT pragma,

# we could say:

# $fh = $sth->blob_as_handle(0,4096);

...

$sth->finish;

$dbh->disconnect;

=head1 DESCRIPTION AND RATIONALE

DBI has blob_copy_to_file method which takes a file handle argument
and copies a database large binary object (LOB) to this file handle.
However, the method is faulty. DBIx::BLOB::Handle constructs a tied
filehandle that also extends from IO::Handle and IO::Selectable. It
wraps DBI's blob_read method. By making LOB's available as a file 
handle to read from we can process the data in a familiar perly way.
Additionally, by making the module respect $/ and $. then we can 
read lines of text data from a textual LOB (CLOB) and treat it just
as we would any other file handle (this last bit still to do!)

=head1 CONSTRUCTOR

=item new 

=over

=over

$fh = DBIx::BLOB::Handle->new($sth,$column,$blocksize);

$fh = $statement->blob_as_handle($column,$blocksize);

=back

=back

Constructs a new file handle from the given DBI statement, given the column
number (zero based) of the LOB within the statement. The column number defaults
to '0'. The blocksize argument specifies how many bytes at a time should be read
from the LOB and defaults to '4096'

...

By 'use'ing the :INTO_STATEMENT pragma as follows;

use DBIx::BLOB::Handle qw( :INTO_STATEMENT );

DBIx::BLOB::Handle will install itself as a method of the DBI::st (statement) 
class. Thus you can create a file handle by calling

    $fh = $statement->blob_as_handle($column,$blocksize);

which in turn calls new.

=back

=head1 METHODS

Currently only a subset of the Tied Handle interface is implemented

=over

=item $handle->getline, $handle->getlines, <$handle>

=over

Read from the LOB. 
getline, or <$handle> in scalar context will return up to $blocksize bytes from
the current position within the LOB (see the 'new' constructor).
getlines or <$handle> in list context will return the entire LOB

=back

=item tell

=over

$handle->tell; 

tell $handle;

=back

=back

Gives the current position (in bytes, zero based) within the LOB

=over

=item eof

=over

$handle->eof; 

eof $handle;

=back

=back

Returns true if we have finished reading from the LOB.

=head1 SEE ALSO

Perls Filehandle functions,
L<IO::Handle>,
L<IO::Seekable>

=head1 AUTHOR

Mark Southern (mark_southern@merck.com)

=head1 COPYRIGHT

Copyright (c) 2002, Merck & Co. Inc. All Rights Reserved.
This module is free software. It may be used, redistributed
and/or modified under the terms of the Perl Artistic License
(see http://www.perl.com/perl/misc/Artistic.html)

=cut
