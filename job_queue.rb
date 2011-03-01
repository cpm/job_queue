require 'socket'
require 'thread'

module JobQueue
  class JobQueueException < RuntimeError; end

  module ThreadSafer
    def safely(*methods)
      methods.each do |method|
        self.send(:define_method, method.to_sym) do |*args|
          (@lock ||= Mutex.new).synchronize { super(*args) }
        end
      end
    end
  end

  # Just a subclass of Hash that takes certain methods and make them thread-safe
  # all on a single mutex via the safely macro. Macro doesn't play well with
  # methods that take a block.
  class ThreadSaferHash < Hash
    class << self; include ThreadSafer; end

    def initialize(*args, &block)
      super
    end

    def to_hash
      h = {}
      self.each do |key, value|
        h[key] = value
      end
      h
    end

    safely :[], :[]=, :delete
  end

  class JobServer

    attr_reader :jobs, :statuses, :everything

    def initialize
      @current_key = 1
      @jobs = ThreadSaferHash.new
      @statuses = ThreadSaferHash.new

      @key_mutex = Mutex.new

      @everything = ThreadSaferHash.new
    end

    def listen(port)
      server = TCPServer.new(port)

      ActiveRecord::Base.allow_concurrency = true

      while sock = server.accept
        Thread.new do
          begin
            handle_request(sock)
          rescue
            puts $!
            sock.print("ERROR #{$!}\n\n") rescue nil
            sock.close rescue nil
          end
        end
      end
    end

    def next_key
      @key_mutex.synchronize do
        @current_key += 1
      end
    end

    # JobQueue protocol looks like this:
    # C: CHECK ticketid\n\n
    # S: DONE chars-count\n\nMARSHALED-DATA  or
    # S: WORKING\n\n
    # S: NOTFOUND\n\n
    #
    # C: QUEUE chars-count\n\nMARSHALED-DATA
    # S: ticketid\n\n
    # S: ERROR reason\n\n
    #
    # C: JOBS
    # S: chars-count MARSHALED-DATA
    # The MARSHALLED-DATA is a
    def handle_request(socket)
      (verb, arg) = socket.readline("\n\n").rstrip.split(" ")

      dispatch = {"QUEUE" => method(:queue), "CHECK" => method(:check), "LIST" => method(:list)}

      puts "Request: #{verb} - #{arg}"
      if dispatch[verb]
        ActiveRecord::Base.verify_active_connections!
        dispatch[verb].call(socket, arg)
      else
        socket.print("ERROR '#{verb}' must be QUEUE or CHECK\n\n")
        socket.close rescue nil
      end
    end

    def check(socket, arg)
      key = arg.to_i
      puts "CHECKING...#{arg.to_i}"
      if self.everything[key]
        case self.everything[key][:status]
        when :done
          result = self.everything[key][:result]
          dump = Marshal.dump(result)
          self.everything.delete(key)

          puts "DONE #{key}: #{result}"
          socket.print "DONE #{dump.size}\n\n#{dump}"

        when :running
          socket.print "WORKING\n\n"
          puts "WORKING #{key}"
        else
          puts "#{self.everything[key][:status]} = not found"
          socket.print "NOTFOUND\n\n"
          puts "NOTFOUND #{key}"
        end

      else
        puts "#{key} not found!"
        socket.print "NOTFOUND\n\n"
        puts "NOTFOUND #{key}"
      end

      socket.close rescue nil
    end

    def list(socket, arg)
      data = {}
      self.everything.to_hash.each do |key, hsh|
        data[key] = hsh.to_hash
      end

      dump = Marshal.dump(data)
      socket.print "#{dump.size} #{dump}\n\n"

      socket.close rescue nil
    end

    def queue(socket, arg)
      begin
        hsh = Marshal.load( socket.read(arg.to_i) )
      rescue
        socket.print("ERROR #{$!}")
        socket.close
        return
      end

      key = self.next_key
      self.everything[key] = ThreadSaferHash.new
      self.everything[key][:status] = :running
      self.everything[key][:arg] = hsh

      socket.print("#{key}\n\n")
      socket.close

      # from this point, so this is out of band.
      klass = hsh[:worker]

      begin
        worker = klass.new(hsh[:args])
        self.everything[key][:result] = worker.run
      rescue
        puts "ERROR: #{$!}"
        self.everything[key][:result] = $!
        puts "Setting everything[#{key}][:result] as exception"
      end
      self.everything[key][:status] = :done
    end
  end
end

if __FILE__ == $0
  JobQueue::JobServer.new.listen(2202)
end
