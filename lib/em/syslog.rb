require "rubygems"
require "eventmachine"
require "socket"

module EventMachine
  module Protocols
    module Syslog
      # THIEVERY: http://github.com/kpumuk/ruby_syslog
      SEVERITIES = {
        :emergency => 0,      # system is unusable
        :alert => 1,          # action must be taken immediately
        :critical => 2,       # critical conditions
        :error => 3,          # error conditions
        :warning => 4,        # warning conditions
        :notice => 5,         # normal but significant condition
        :informational => 6,  # informational messages
        :info => 6,           # informational messages (short name for the previous)
        :debug => 7           # debug-level messages
      }
 
      class << self
        # THIEVERY: http://github.com/kpumuk/ruby_syslog
        def log(severity, message, time = nil)
          EM.syslog_setup if EM.syslog_queue.nil?
          
          severity = SEVERITIES[severity] if severity.is_a? Symbol
          time ||= Time.now
          hostname = Socket.gethostname
          day = time.strftime('%b %d').sub(/0(\d)/, ' \\1')
          tag = "#{$0.split('/').last}[#{Process.pid}]"
          
          send_message "<#{0 * 8 + severity}>#{day} #{time.strftime('%T')} #{hostname} #{tag}: #{message}"
        end

        def send_message(message)
          EM.syslog_queue.push message
        end
        private :send_message
                      
      end
      
    end
  end
  
  # Class methods for EM
  class << self
    attr_reader :syslog_server, :syslog_port, :syslog_queue
    def syslog_setup(*args)
      syslog_server, syslog_port = args[0], args[1] || 514
      if syslog_server.nil?
        raise 'Syslog server not set' if RUBY_PLATFORM.downcase.include?('mswin32')
        unix_socket_path = RUBY_PLATFORM.downcase.include?('darwin') ? '/var/run/syslog' : '/dev/log'
        socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_DGRAM, 0)
        socket.connect_nonblock(Socket.pack_sockaddr_un(unix_socket_path))
      else
        socket = EM.open_datagram_socket('0.0.0.0', 0)
        remote = true
      end
      @syslog_queue = EM::Queue.new
      message_sender = Proc.new do |message|
        if remote
          socket.send_datagram(message, syslog_server, syslog_port)
        else
          begin
            socket.write_nonblock(message)
          rescue IO::WaitWritable, Errno::EINTR
            @syslog_queue.push(message)
          end
        end
        EM.next_tick do
          @syslog_queue.pop(&message_sender)
        end
      end
      @syslog_queue.pop(&message_sender)
    end

    # THIEVERY: http://github.com/kpumuk/ruby_syslog
    EM::P::Syslog::SEVERITIES.keys.each do |severity|
      define_method severity do |message|
        EM::P::Syslog.log(severity, message)
      end
    end

  end

end
