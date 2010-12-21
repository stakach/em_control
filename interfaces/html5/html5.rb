
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
		@@clients.delete(id)
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
	
	def receive(data)
		@command_lock.synchronize {
			p data	# TODO:: remove this
			
			data = JSON.parse(data)
			if @system.nil? && data["command"] == "system"
				@system = Control::Communicator.select(self, data["data"][0])
			else
				command = data["command"].split('.')
				if command.length == 2
					@system.send_command(command[0], command[1], data["data"])
				else
					# Register
					# Unregister
					array = data["data"]
					array.insert(0, self)
					@system.public_send(command[0].downcase, *array)
				end
			end
		}
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
		p 'HTML5 Browser connected'
		
		socket.onmessage { |data|
			#
			# Attach socket here to system
			#	then process commands
			#
			EM.defer do
				begin
					HTML5Monitor.receive(id, data)
				rescue => e
					p e.message
					p e.backtrace
				end
			end
		}

		socket.onclose {
			HTML5Monitor.unregister(id)
			p "There are now #{HTML5Monitor.count} HTML5 clients connected"
		}
	}

end

puts 'running HTML5 socket server on port 81'
