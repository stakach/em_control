
require 'em-websocket'
require 'json'


#
# This system was designed based on the following articles
#			https://gist.github.com/299789
#			http://blog.new-bamboo.co.uk/2010/2/10/json-event-based-convention-websockets
#


class HTML5Monitor
	@@clients = {}

	def self.register(socket)
		@@clients[socket] = HTML5Monitor.new(socket)
	end
	
	def self.unregister(id)
		client = @@clients.delete(id)
		client.disconnected
	end
	
	def self.count
		@@clients.length
	end
	
	def self.receive(id, data)
		@@clients[id].receive(data)
	end


	#
	# The core communication functions
	#
	def initialize(socket)
		@socket = socket
		@system = nil
		@command_lock = Mutex.new
	end
	
	def disconnected
		@system.disconnected(self) unless @system.nil?
	end
	
	def receive(data)
		@command_lock.synchronize {
			data = JSON.parse(data, {:symbolize_names => true})
			if @system.nil? && data[:command] == "system"
				@system = Control::Communicator.select(self, data[:data][0])
			else
				command = data[:command].split('.')
				if command.length == 2
					@system.send_command(command[0], command[1], data[:data])
				else
					# Register
					# Unregister
					array = data[:data]
					array.insert(0, self)
					@system.public_send(command[0].downcase, *array)
				end
			end
		}
	rescue => e
		@system.logger.error "-- in html5.rb, recieve : probably malformed JSON data --"
		@system.logger.error e.message
		@system.logger.error e.backtrace
	end
	
	def notify(mod_sym, stat_sym, data)
		@socket.send(JSON.generate({"event" => "#{mod_sym}.#{stat_sym}", "data" => data}))
	end
end


EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 81) do |socket|
	
	
	socket.onopen {
		#
		# Setup status variable here :)
		#	We could use a 
		#
		HTML5Monitor.register(socket)
		id = socket
		System.logger.debug 'HTML5 browser connected'
		
		socket.onmessage { |data|
			#
			# Attach socket here to system
			#	then process commands
			#
			EM.defer do
				HTML5Monitor.receive(id, data)
			end
		}

		socket.onclose {
			HTML5Monitor.unregister(id)
			p "There are now #{HTML5Monitor.count} HTML5 clients connected"
		}
	}

end

Control::System.logger.info 'running HTML5 socket server on port 81'
