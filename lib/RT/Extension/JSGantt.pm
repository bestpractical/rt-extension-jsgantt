package RT::Extension::JSGantt;

our $VERSION = '0.04';

use warnings;
use strict;

sub AllRelatedTickets {
    my $class = shift;
    my %args = ( Ticket => undef, CurrentUser => undef, @_ );

    my @tickets;
    my %checked;
    my @to_be_checked;
    my $ticket = RT::Ticket->new( $args{CurrentUser} );
    $ticket->Load( $args{Ticket} );
    if ( $ticket->id ) {

        # find the highest ancestors to make chart pretty
        my @parents = _RelatedTickets( $ticket, 'MemberOf' );
        @parents = $ticket unless @parents;
        my $depth = 0;
        while (@parents ) {
            my @ancestors;
            for my $parent (@parents) {
                unshift @ancestors, _RelatedTickets( $parent, 'MemberOf' );
            }

            if (@ancestors && $depth++ < 10 ) {
                @parents = @ancestors;
            }
            else {
                @to_be_checked = @parents;
                undef @parents;
            }
        }

        _GetOrderedTickets( \@tickets, \@to_be_checked, \%checked );
    }
    return @tickets;
}


sub TicketsInfo {
    my $class = shift;
    my %args = ( Tickets => [], CurrentUser => undef, @_ );


    my ( @ids, %info );
    my @colors = grep { defined } RT->Config->Get('JSGanttColorScheme');
    @colors = ( 'ff0000', 'ffff00', 'ff00ff', '00ff00', '00ffff', '0000ff' )
      unless @colors;
    my $i;
    my $show_progress = RT->Config->Get('JSGanttShowProgress' );

    my ( $min_start, $min_start_obj );

    for my $Ticket (@{$args{Tickets}}) {
        my $progress = 0;
        my $subject = $Ticket->Subject;

        my $parent = 0;
        if ( $Ticket->MemberOf->Count ) {
            # skip the remote links
            next unless $Ticket->MemberOf->First->TargetObj;
            $parent = $Ticket->MemberOf->First->TargetObj->id;
        }

        # find start/end, this is, uhh, long long way to go
        my ( $start_obj, $start ) = _GetDate( $Ticket, 'Starts', 'Started' );
        my ( $end_obj, $end ) = _GetDate( $Ticket, 'Due' );

        # if $start or $end is empty still
        unless ( $start && $end ) {
            my $hours_per_day = RT->Config->Get('JSGanttWorkingHoursPerDay')
              || 8;
            my $total_time =
              defined $Ticket->TimeLeft && $Ticket->TimeLeft =~ /\d/
              ? ( $Ticket->TimeWorked + $Ticket->TimeLeft )
              : $Ticket->TimeEstimated;
            $total_time ||= 0;
            my $days = int( $total_time / ( 60 * $hours_per_day ) );
            $days ||= RT->Config->Get('JSGanttDefaultDays') || 7;

            # since we only use date without time, let's make days inclusive
            # ( i.e. 5/12/2010 minus 3 days is 5/10/2010. 10,11,12, 3 days! )
            $days = $days =~ /\./ ? int $days : $days - 1;
            $days = 0 if $days < 0;

            if ( $start && !$end ) {
                $end_obj = RT::Date->new( $args{CurrentUser} );
                $end_obj->Set( Value => $start_obj->Unix );
                $end_obj->AddDays($days);
                my ( $day, $month, $year ) =
                  ( $end_obj->Localtime('user') )[ 3, 4, 5 ];
                $end = join '/', $month + 1, $day, $year;
            }

            if ( $end && !$start ) {
                $start_obj = RT::Date->new( $args{CurrentUser} );
                $start_obj->Set( Value => $end_obj->Unix );
                $start_obj->AddDays( -1 * $days );
                my ( $day, $month, $year ) =
                  ( $start_obj->Localtime('user') )[ 3, 4, 5 ];
                $start = join '/', $month + 1, $day, $year;
            }
        }

        if ( !$start ) {
            $RT::Logger->warning( "Ticket "
                  . $Ticket->id
                  . " doesn't have Starts/Started defined, and we can't figure it out either"
            );
            $start = $end;
        }
        if ( !$end ) {
            $RT::Logger->warning( "Ticket "
                  . $Ticket->id
                  . " doesn't have Due defined, and we can't figure it out either"
            );
            $end = $start;
        }

        if ( $start_obj
            && ( !$min_start_obj || $min_start_obj->Unix > $start_obj->Unix ) )
        {
            $min_start_obj = $start_obj;
            $min_start     = $start;
        }

        my $has_members = $Ticket->Members->Count ? 1 : 0;

        my $depends = $Ticket->DependsOn;
        my @depends;
        if ( $depends->Count ) {
            while ( my $d = $depends->Next ) {
                # skip the remote links
                next unless $d->TargetObj; 
                push @depends, $d->TargetObj->id;
            }
        }

        if ($show_progress) {
            my $total_time =
              defined $Ticket->TimeLeft && $Ticket->TimeLeft =~ /\d/
              ? ( $Ticket->TimeWorked + $Ticket->TimeLeft )
              : $Ticket->TimeEstimated;
            if ($total_time && $total_time =~ /\d/ ) {
                if ( $Ticket->TimeWorked ) {
                    $progress = int( 100 * $Ticket->TimeWorked / $total_time );
                }
            }
        }

        push @ids, $Ticket->id;
        $info{ $Ticket->id } = {
            name  => ( $Ticket->id . ': ' . substr $subject, 0, 30 ),
            start => $start,
            end   => $end,
            color => $colors[ $i++ % @colors ],
            link  => (
                    RT->Config->Get('WebPath')
                  . '/Ticket/Display.html?id='
                  . $Ticket->id
            ),
            milestone => 0,
            owner =>
              ( $Ticket->OwnerObj->Name || $Ticket->OwnerObj->EmailAddress ),
            progress    => $progress,
            has_members => $has_members,
            parent      => $parent,
            open        => 1,
            depends     => ( @depends ? join ',', @depends : 0 )
        };
    }

    #let's tweak our results
    #set to now if all tickets don't have start/end dates
    unless ( $min_start_obj && $min_start_obj->Unix > 0 ) {
        $min_start_obj = RT::Date->new( $args{CurrentUser} );
        $min_start_obj->SetToNow;
        my ( $day, $month, $year ) =
          ( $min_start_obj->Localtime('user') )[ 3, 4, 5 ];
        $min_start = join '/', $month + 1, $day, $year;
    }

    my $no_dates_color = RT->Config->Get('JSGanttNullDatesColor') || '333';
    for my $id (@ids) {
        $info{$id}{color} = $no_dates_color unless $info{$id}{start};
        $info{$id}{start} ||= $min_start;
        $info{$id}{end}   ||= $min_start;
    }
    return \@ids, \%info;
}

sub _RelatedTickets {
    my $ticket = shift;
    my @types = @_;
    return unless $ticket;
    my @tickets;
    for my $type ( @types ) {
        my $links = $ticket->$type->ItemsArrayRef;
        my $target_or_base =
          $type =~ /DependsOn|MemberOf|RefersTo/ ? 'TargetObj' : 'BaseObj';
        for my $link (@$links) {
            my $obj = $link->$target_or_base;
            if ( $obj && $obj->isa('RT::Ticket') ) {
                push @tickets, $obj;
            }
        }
    }
    return @tickets;
}


sub _GetDate {
    my $ticket = shift;
    my $depth;
    if ( $_[0] =~ /^\d+$/ ) {
        $depth = shift;
    } 
    else {
        $depth = 0;
    }

    my @fields = @_;
    my ( $date_obj, $date );
    for my $field (@fields) {
        my $obj = $field . 'Obj';
        if ( $ticket->$obj->Unix > 0 ) {
            $date_obj = $ticket->$obj;
            my ( $day, $month, $year ) =
              ( $date_obj->Localtime('user') )[ 3, 4, 5 ];
            $date = join '/', $month + 1, $day, $year;
        }
    }

    if ($date || $depth++ > 10 ) {
        return ( $date_obj, $date );
    }

    # inherit from parents
    for my $member_of ( @{ $ticket->MemberOf->ItemsArrayRef } ) {
        my $parent = $member_of->TargetObj;
        return _GetDate( $parent, $depth, @fields );
    }
}


sub _GetOrderedTickets {
    my $tickets       = shift;
    my $to_be_checked = shift;
    my $checked       = shift;
    while ( my $ticket = shift @$to_be_checked ) {
        push @$tickets, $ticket
          unless grep { $ticket->id eq $_->id } @$tickets;
        next if $checked->{$ticket->id}++;

        for my $member ( grep { !$checked->{ $_->id } }
            _RelatedTickets( $ticket, 'Members' ) )
        {
            unshift @$to_be_checked, $member;
            _GetOrderedTickets( $tickets,$to_be_checked, $checked );
        }

        for my $parent ( grep { !$checked->{ $_->id } }
            _RelatedTickets( $ticket, 'MemberOf' ) )
        {
            unshift @$to_be_checked, $parent;
            _GetOrderedTickets( $tickets, $to_be_checked, $checked );
        }

        for my $related ( grep { !$checked->{ $_->id } }
            _RelatedTickets( $ticket, 'DependsOn', 'DependedOnBy', 'RefersTo',
            'ReferredToBy' ))
        {
            push @$to_be_checked, $related;
            _GetOrderedTickets( $tickets, $to_be_checked, $checked );
        }
    }
}


=head1 NAME

RT::Extension::JSGantt - Gantt charts for your tickets


=head1 SYNOPSIS

    use RT::Extension::JSGantt;

  
=head1 DESCRIPTION


=head1 AUTHOR

sunnavy C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Best Practical Solutions, LLC.  All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut

1;
