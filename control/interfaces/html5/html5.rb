
require 'em-websocket'
require 'json'


#
# This system was designed based on the following articles
#			https://gist.github.com/299789
#			http://blog.new-bamboo.co.uk/2010/2/10/json-event-based-convention-websockets
#


class HTML5Monitor
	@@clients = {}
	@@client_lock = Mutex.new
	@@special_events = {
		"system" => :system,
		"authenticate" => :authenticate,
		"ls" => :ls,
		"ping" => :ping
	}
	@@special_commands = {
		"register" => :register,
		"unregister" => :unregister
	}

	def self.register(socket)
		@@client_lock.synchronize {
			@@clients[socket] = HTML5Monitor.new(socket)
		}
	end
	
	def self.unregister(id)
		@@client_lock.synchronize {
			client = @@clients.delete(id)
			client.disconnected
		}
	end
	
	def self.count
		@@client_lock.synchronize {
			return @@clients.length
		}
	end
	
	def self.receive(id, data)
		@@client_lock.synchronize {
			@@clients[id].receive(data)
		}
	end
	
	def send_system
		@socket.send(JSON.generate({:event => "system", :data => []}))
	end
	
	def try_auth(data = nil)
		#
		# TODO:: authentication
		#
		# try auth
		#	send auth on fail
		# else 
		@socket.send(JSON.generate({:event => "ready", :data => []}))
	end


	#
	# The core communication functions
	#
	def initialize(socket)
		@socket = socket
		@system = nil
		@authenticated = false
		
		@data_lock = Mutex.new
		
		#
		# Send system event as per the spec
		#
		send_system
	end
	
	def disconnected
		@data_lock.synchronize {
			@system.disconnected(self) unless @system.nil?
		}
	end
	
	def receive(data)
		data = JSON.parse(data, {:symbolize_names => true})
		return unless data[:command].class == String
		data[:data] = [] unless data[:data].class == Array

		@data_lock.synchronize {
			if @@special_events.has_key?(data[:command])		# system, auth, ls
				case @@special_events[data[:command]]
					when :system
						@system = Control::Communicator.select(self, data[:data][0]) unless data[:data].empty?
						if @system.nil?
							send_system
						else
							try_auth
						end
					when :authenticate
						if @system.nil?
							send_system
						else
							try_auth(data[:data])
						end
					when :ping
						@socket.send(JSON.generate({:event => "pong", :data => []}))
					when :ls
						@socket.send(JSON.generate({:event => "system",
							:data => Communicator.system_list}))
				end
			elsif @@special_commands.has_key?(data[:command])	# reg, unreg
				array = data[:data]
				array.insert(0, self)
				@system.public_send(data[:command], *array)
			else									# All other commands
				command = data[:command].split('.')
				if command.length == 2
					@system.send_command(command[0], command[1], *data[:data])
				else
					Control::System.logger.info "-- in html5.rb, recieve : invalid command recieved - #{data[:command]} --"
				end
			end
		}
	rescue => e
		logger = nil
		@data_lock.synchronize {
			logger = @system.nil? ? logger = Control::System.logger : @system.logger
		}
		logger.error "-- in html5.rb, recieve : probably malformed JSON data --"
		logger.error e.message
		logger.error e.backtrace
	end
	
	def notify(mod_sym, stat_sym, data)
		#
		# This should be re-entrant? So no need to protect
		#
		@socket.send(JSON.generate({"event" => "#{mod_sym}.#{stat_sym}", "data" => data}))
	end
end


EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 81) do |socket|
	
	
	socket.onopen {
		#
		# Setup status variable here :)
		#	We could use a 
		#
		id = nil
		
		EM.defer do
			HTML5Monitor.register(socket)
			id = socket
			Control::System.logger.debug 'HTML5 browser connected'
		end
		
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
			EM.defer do
				HTML5Monitor.unregister(id)
				Control::System.logger.info "There are now #{HTML5Monitor.count} HTML5 clients connected"
			end
		}
	}

end

Control::System.logger.info 'running HTML5 socket server on port 81'
