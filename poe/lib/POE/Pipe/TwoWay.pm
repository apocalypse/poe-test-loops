# $Id$

# Portable two-way pipe creation, trying as many different methods as
# we can.

package POE::Pipe::TwoWay;

use strict;
use Symbol qw(gensym);
use IO::Socket;

sub DEBUG () { 0 }
sub RUNNING_IN_HELL () { $^O eq 'MSWin32' }

# This flag is set true/false after the first attempt at using plain
# INET sockets as pipes.
my $can_run_socket = undef;

sub new {
  my $type = shift;
  my $conduit_type = shift;

  # Generate symbols to be used as filehandles for the pipe's ends.
  my $a_read  = gensym();
  my $a_write = gensym();
  my $b_read  = gensym();
  my $b_write = gensym();

  # Try the pipe if no preferred conduit type is specified, or if the
  # specified conduit type is 'pipe'.
  if ( (not defined $conduit_type) or
       ($conduit_type eq 'pipe')
     ) {
      
    # Try using pipe, but don't bother on systems that don't support
    # nonblocking pipes.  Even if they support pipes themselves.
    unless (RUNNING_IN_HELL) {

      # Try pipes.
      eval {
        pipe($a_read, $b_write) or die "pipe 1 failed: $!";
        pipe($b_read, $a_write) or die "pipe 2 failed: $!";
      };

      # Pipe succeeded.
      unless (length $@) {
        DEBUG and do {
          warn "using a pipe\n";
          warn "ar($a_read) aw($a_write) br($b_read) bw($b_write)\n";
        };

        # Turn off buffering.  POE::Kernel does this for us, but
        # someone might want to use the pipe class elsewhere.
        select((select($a_write), $| = 1)[0]);
        select((select($b_write), $| = 1)[0]);
        return($a_read, $a_write, $b_read, $b_write);
      }
    }
  }

  # Try UNIX-domain socketpair if no preferred conduit type is
  # specified, or if the specified conduit type is 'socketpair'.
  if ( (not defined $conduit_type) or
       ($conduit_type eq 'socketpair')
     ) {
    eval {
      socketpair($a_read, $b_read, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or die "socketpair 1 failed: $!";
    };

    # Socketpair succeeded.
    unless (length $@) {
      DEBUG and do {
        warn"using UNIX domain socketpairs\n";
        warn "ar($a_read) aw($a_write) br($b_read) bw($b_write)\n";
      };

      # It's two-way, so each reader is also a writer.
      $a_write = $a_read;
      $b_write = $b_read;

      # Turn off buffering.  POE::Kernel does this for us, but someone
      # might want to use the pipe class elsewhere.
      select((select($a_write), $| = 1)[0]);
      select((select($b_write), $| = 1)[0]);
      return($a_read, $b_write);
    }
  }

  # Try a pair of plain INET sockets if no preffered conduit type is
  # specified, or if the specified conduit type is 'inet'.
  if ( (not defined $conduit_type) or
       ($conduit_type eq 'inet')
     ) {

    # Don't bother if we already know it won't work.
    if ($can_run_socket or (not defined $can_run_socket)) {

      # Try using a pair of plain INET domain sockets.  Usurp SIGALRM
      # in case it blocks.  Normally POE programs don't use SIGALRM
      # anyway.  [fingers crossed here]
      my $old_sig_alarm = $SIG{ALRM};
      eval {
        local $SIG{ALRM} = sub { die "deadlock" };
        eval 'alarm(1)' unless RUNNING_IN_HELL;

        my $acceptor = IO::Socket::INET->new
          ( LocalAddr => '127.0.0.1',
            LocalPort => 31415,
            Listen    => 5,
            Reuse     => 'yes',
          );

        $a_read = IO::Socket::INET->new
          ( PeerAddr  => '127.0.0.1',
            PeerPort  => 31415,
            Reuse     => 'yes',
          );

        $b_read = $acceptor->accept() or die "accept";

        $a_write = $a_read;
        $b_write = $b_read;
      };
      eval 'alarm(0)' unless RUNNING_IN_HELL;
      $SIG{ALRM} = $old_sig_alarm;

      # Sockets worked.
      unless (length $@) {
        DEBUG and do {
          warn "using a plain INET socket\n";
          warn "ar($a_read) aw($a_write) br($b_read) bw($b_write)\n";
        };

        # Try sockets more often.
        $can_run_socket = 1;

        # Turn off buffering.  POE::Kernel does this for us, but someone
        # might want to use the pipe class elsewhere.
        select((select($a_write), $| = 1)[0]);
        select((select($b_write), $| = 1)[0]);
        return($a_read, $a_write, $b_read, $b_write);
      }

      # Sockets failed.  Don't dry them again.
      else {
        $can_run_socket = 0;
      }
    }
  }

  # There's nothing left to try.
  DEBUG and warn "nothing worked\n";
  return(undef, undef, undef, undef);
}

###############################################################################
1;

__END__
