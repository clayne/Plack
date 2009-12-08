package Plack::Component;
use strict;
use warnings;
use Carp ();
use Plack::Util;
use overload '&{}' => sub { shift->to_app(@_) }, fallback => 1;

use Plack::Util::Accessor qw( app );

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self;
    if (@_ == 1 && ref $_[0] eq 'HASH') {
        $self = bless {%{$_[0]}}, $class;
    } else {
        $self = bless {@_}, $class;
    }

    $self;
}

# NOTE:
# this is for back-compat only,
# future modules should use
# Plack::Util::Accessor directly
# or their own favorite accessor
# generator.
# - SL
sub mk_accessors {
    my $self = shift;
    Plack::Util::Accessor::mk_accessors( ref( $self ) || $self, @_ )
}

sub to_app {
    my $self = shift;
    return sub { $self->call(@_) };
}

sub response_cb {
    my($self, $res, $cb) = @_;

    my $body_filter = sub {
        my($cb, $res) = @_;
        my $filter_cb = $cb->($res);
        # If response_cb returns a callback, treat it as a $body filter
        if (defined $filter_cb && ref $filter_cb eq 'CODE') {
            if (defined $res->[2]) {
                my $body    = $res->[2];
                my $getline = ref $body eq 'ARRAY' ? sub { shift @$body } : sub { $body->getline };
                $res->[2] = Plack::Util::inline_object
                    getline => sub { $filter_cb->($getline->()) },
                    close => sub { $body->close if ref $body ne 'ARRAY' };
            } else {
                return $filter_cb;
            }
        }
    };

    if (ref $res eq 'ARRAY') {
        $body_filter->($cb, $res);
        return $res;
    } elsif (ref $res eq 'CODE') {
        return sub {
            my $respond = shift;
            $res->(sub {
                my $res = shift;
                my $filter_cb = $body_filter->($cb, $res);
                if ($filter_cb) {
                    my $writer = $respond->($res);
                    if ($writer) {
                        return Plack::Util::inline_object
                            write => sub { $writer->write($filter_cb->(@_)) },
                            close => sub { $writer->write($filter_cb->(undef)); $writer->close };
                    }
                } else {
                    return $respond->($res);
                }
            });
        };
    }

    return $res;
}

1;

__END__

=head1 NAME

Plack::Component - Base class for easy-to-use PSGI middleware and endpoints

=head1 DESCRIPTION

Plack::Component is the base class shared between Plack::Middleware and
Plack::App::* modules. If you are writing middleware, you should inherit
from Plack::Middleware, but if you are writing a Plack::App::* you should
inherit from this directly.

=head1 SEE ALSO

L<Plack> L<Plack::Builder>

=cut