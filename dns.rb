require 'net/dns'
require 'net/dns/resolver'

module EM # :nodoc:
  module Protocols
    
    include Logger::Severity

    class AsyncResolver < Net::DNS::Resolver

      # Create a new resolver object.
      def initialize(config = {})
        # store outstanding requests
        @outstanding = {}
        super(config)
      end

      # Do an asynchronous DNS query.  Returns an AsyncQuery object that implements Deferrable
      # The callback will be passed a DNS::Packet with the returned results
      def query_async(name,type=Net::DNS::A,cls=Net::DNS::IN)
        # If the name doesn't contain any dots then append the default domain.        
        if name.class != IPAddr and name !~ /\./ and name !~ /:/ and @config[:defnames]
          name += "." + @config[:domain]
        end
        @logger.debug "Query(#{name},#{Net::DNS::RR::Types.new(type)},#{Net::DNS::RR::Classes.new(cls)})"
        AsyncQuery.new(send_async(name,type,cls))
      end

      # Do an asynchronous MX query.  Returns a MXQuery object that implements Deferrable
      # The callback will be passed an array of MX records with the returned results, sorted by preference
      def mx_async(name,cls=Net::DNS::IN)
        @logger.debug "Query(#{name},#{Net::DNS::MX},#{Net::DNS::RR::Classes.new(cls)})"
        MXQuery.new(send_async(name, Net::DNS::MX, cls))
      end

      # Send a query to the nameservers and return a deferrable that will be called with the response packet
      def send_async(argument, type = Net::DNS::A, cls = Net::DNS::IN)
        if @config[:nameservers].size == 0
          raise ResolverError, "No nameservers specified!"
        end

        method = :send_udp_async
        packet = if argument.kind_of? Net::DNS::Packet
          argument
        else
          make_query_packet(argument, type, cls)
        end

        # Store packet_data for performance improvements,
        # so methods don't keep on calling Packet#data
        packet_data = packet.data
        packet_size = packet_data.size

        # Choose whether use TCP or UDP
        if packet_size > @config[:packet_size] # Must use TCP, either plain or raw
          @logger.info "Sending #{packet_size} bytes using TCP"
          method = :send_tcp_async
        else # Packet size is inside the boundaries
          if use_tcp? # User requested TCP
            @logger.info "Sending #{packet_size} bytes using TCP"
            method = :send_tcp_async
          else # Finally use UDP
            @logger.info "Sending #{packet_size} bytes using UDP"
          end
        end

        response = EM::DefaultDeferrable.new
        result = self.old_send(method,packet,packet_data)

        # handle a successful response
        result.callback do |packet|
          response.succeed packet
        end
        # return an error message if we fail
        result.errback do
          response.fail "No response from nameservers list"
        end
 
        return response
      end

      def receive_datagram(data)
        response = Net::DNS::Packet.parse(data, nil)
        if r = @outstanding.delete(response.header.id)
          r.succeed(response)
        else
          @logger.warn "Got datagram with no outstanding request: #{response}"
        end
      end

      def resend_udp_packet request
        ns = @config[:nameservers][ rand(@config[:nameservers].size) ]
        udp_socket.send_datagram(request.packet.data, ns.to_s, @config[:port])
      end

      private

      def send_udp_async(packet, packet_data)

        # generate a request
        request = UDPRequest.new packet, self
        @logger.warn "ID collision: #{packet.header.id}" if @outstanding[packet.header.id]
        @outstanding[packet.header.id] = request

        # pick a random nameserver and query it
        ns = @config[:nameservers][ rand(@config[:nameservers].size) ]
        @logger.info "Contacting nameserver #{ns} port #{@config[:port]}"
        udp_socket.send_datagram(packet_data, ns.to_s, @config[:port])

        # return the result
        request
      end

      def udp_socket
        # start listening if we aren't already
        unless @udp_socket
          unbind_signaller = proc {@udp_socket = nil}
          @udp_socket = EM::open_datagram_socket( @config[:source_address].to_s, @config[:source_port], UDPSocket, self ) {|c|
            c.unbind_signaller = unbind_signaller
          }
        end
        @udp_socket
      end

      # should implement TCP
      def send_tcp_async(packet, packet_data)
        raise NotImplementedError.new "TCP is not yet supported"
      end

    end

    class UDPSocket < EM::Connection
      attr_accessor :unbind_signaller

      def initialize resolver
        @resolver = resolver
      end

      def receive_data data
        @resolver.receive_datagram(data)
      end

      def unbind
        @unbind_signaller.call if @unbind_signaller
      end
    end

    class UDPRequest
      include EM::Deferrable
      attr_accessor :attempts, :packet

      def initialize packet, resolver
        @packet = packet
        @resolver = resolver
        @attempts = 0
        self.timeout @resolver.udp_timeout
      end

      def fail
        if @attempts < @resolver.retry_number
          @attempts += 1
          @resolver.resend_udp_packet self
          self.timeout @resolver.udp_timeout
        else
          super
        end
      end

    end

    # wraps a udp request to return a more useful response
    class MXQuery
      include EM::Deferrable

      def initialize(udprequest)

        udprequest.callback do |packet|
          arr = []
          packet.answer.each do |entry|
            arr << entry if entry.type == 'MX'
          end
          succeed(arr)
        end

        udprequest.errback do |error|
          fail(error)
        end
      end
    end

    # wraps a udp request to return a more useful response
    class AsyncQuery
      include EM::Deferrable

      def initialize(udprequest)
        # handle a successful response
        udprequest.callback do |packet|
          succeed packet
        end
        # return an error message if we fail
        udprequest.errback do
          fail "No response from nameservers"
        end
      end

    end

  end

end

=begin

if __FILE__ == $0
  EM.run do
    res = EM::P::AsyncResolver.new
    count = 0
    5.times do
      ["gmail.com", "yahoo.com", "otherinbox.com", "asdfvaesr.com"].each do |domain|
        count += 1
        result = res.mx_async(domain)
        result.callback { |answer| puts "Got MX records for #{domain}: #{answer.inspect}"; count -= 1; }
        result.errback { |err| STDERR.puts "Got error for #{domain}: #{err}"; count -= 1; }
      end
    end
    5.times do
      ["gmail.com", "yahoo.com", "otherinbox.com", "asdfvaesr.com"].each do |domain|
        count += 1
        result = res.query_async(domain)
        result.callback { |packet| puts "Got result for #{domain}: #{packet.answer}"; count -= 1; }
        result.errback { |err| STDERR.puts "Got error for #{domain}: #{err}"; count -= 1; }
      end
    end
    EM.add_periodic_timer(1) { EM.stop_event_loop if count == 0 }
  end
end

=end
