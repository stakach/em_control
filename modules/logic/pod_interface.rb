
require 'json'

class PodInterface < Control::Logic		
	module AMXInterface
		def post_init
			#
			# Someone connected -- check they are valid
			#
			port, ip = Socket.unpack_sockaddr_in(get_peername)
		end
	
		def receive_data(data)
			(@buffer ||= BufferedTokenizer.new('' << 0x03)).extract(data).each do |line|
				line = line.split("" << 0x02)
				if line.length >= 2
					
					EM.defer do
						begin
							line = JSON.parse(line[-1], {:symbolize_names => true})
							
							#
							# Process commands here
							#
							
							ActiveRecord::Base.clear_active_connections!
						rescue => e
							Control.print_error(logger, e, {
								:message => "module PodInterface error processing AMX command",
								:level => Logger::ERROR
							})
						end
					end
					
					
				end
			end
		end
	end

	def on_load
		@server = EventMachine::start_server '127.0.0.1', 24842, AMXInterface
	end
	
	
	def on_unload
		EventMachine::stop_server(@server) unless @server.nil?
	end
	
	
	def on_update
		EventMachine::stop_server(@server) unless @server.nil?
		@server = EventMachine::start_server '127.0.0.1', 24842, AMXInterface
	end
end
