require 'socket'

module JobQueue
  class Client
    def initialize(host, port)
      @host = host
      @port = port
    end

    def socket
      TCPSocket.new(@host, @port)
    end

    def queue(hsh = {})
      data = Marshal.dump(hsh)
      sock = self.socket
      sock.print("QUEUE #{data.size}\n\n#{data}")
      line = sock.gets("\n\n")
      sock.close
      return line.to_i
    end

    def check(key)
      sock = self.socket
      sock.print("CHECK #{key}\n\n")
      line = sock.gets("\n\n").rstrip

      job = {}

      case line
      when /\ANOTFOUND/
        job[:status] = :not_found

      when /\AWORKING/
        job[:status] = :working

      when /\ADONE (\d+)/
        serialized_data = sock.read($1.to_i)
        job[:status] = :done

        # Marshal will throw an exception if it encounters an unknown class
        # TODO: catpure the exception? maybe.
        job[:result] = Marshal.load(serialized_data)

      else
        job[:status] = :invalid

      end

      sock.close
      return job
    end

    def list
      sock = self.socket
      socket.print("LIST\n\n")
      length = sock.readline(" ").to_i

      # Marshal will throw an exception if it encounters an unknown class
      # TODO: catpure the exception? maybe.
      Marhsal.load(sock.read(length))
    end
  end
end

if __FILE__ == $0
  require 'my_worker'

  client = JobQueue::Client.new("localhost", 2202)
  key = client.queue({:worker => MyWorker})
  while( line = client.check(key) =~ /WORKING/ )
    puts "check"
  end
end
