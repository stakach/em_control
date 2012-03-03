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

	def self.register(id)
		@@client_lock.synchronize {
			@@clients[id] = HTML5Monitor.new(id)
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
		client = nil
		@@client_lock.synchronize {
			client = @@clients[id]
		}
		client.receive(data)
	end
	
	
	#
	#
	# Instance methods:
	#
	#
	def try_auth(data = nil)
		
		return false if @ignoreAuth

		if !!@user
			if data.nil?
				return true
			else
				@user = nil
				return try_auth(data)
			end
		else
			if !data.nil? && data.class == Array
				if data.length == 1	# one time key
					@user = TrustedDevice.try_to_login(data[0])
				elsif data.length == 3
											#user, password, auth_source
					source = AuthSource.where("name = ?", data[2]).first
					@user = User.try_to_login(data[0], data[1], source)
				end
				
				return try_auth	# no data
			end
			
			#
			# Prevent DOS/brute force Attacks
			#
			@ignoreAuth = true
			Control.scheduler.in '2s' do
				begin
					@socket.send(JSON.generate({:event => "authenticate", :data => []}))
				ensure
					@data_lock.synchronize {
						@ignoreAuth = false
					}
				end
			end
		end
		return false
	end
	
	def send_system
		return if @ignoreSys	
		@ignoreSys = true
		
		Control.scheduler.in '2s' do
			begin
				@socket.send(JSON.generate({:event => "system", :data => []}))
			ensure
				@data_lock.synchronize {
					@ignoreSys = false
				}
			end
		end
	end


	#
	# The core communication functions
	#
	def initialize(socket)
		@data_lock = Mutex.new
		
		#
		# Must authenticate before any system details will be sent
		#
		@data_lock.synchronize {
			@socket = socket
			@system = nil
			@user = nil
			try_auth	# will not be authenticated here
		}
	end
	
	def disconnected
		@data_lock.synchronize {
			@system.disconnected(self) if (!!@system)	# System could be nil or false
		}
	end
	
	def receive(data)
		data = JSON.parse(data, {:symbolize_names => true})
		return unless data[:command].class == String
		data[:data] = [] unless data[:data].class == Array

		@data_lock.synchronize {
			#
			# Ensure authenticated
			#
			if data[:command] == "authenticate"
				return unless try_auth(data[:data])
				send_system
				return
			else
				return unless (try_auth || data[:command] == "ping")
			end
			
			#
			# Ensure system is selected
			#	If a command is sent out of order
			#
			if @system.nil? && !@@special_events.has_key?(data[:command])
				send_system
				return
			end
			
			if @@special_events.has_key?(data[:command])		# system, auth, ls
				case @@special_events[data[:command]]
					when :system
						@system.disconnected(self) unless @system.nil?
						@system = nil
						@system = Control::Communicator.select(@user, self, data[:data][0]) unless data[:data].empty?
						if @system.nil?
							send_system
						elsif @system == false	# System offline
							@socket.send(JSON.generate({:event => "offline", :data => []}))
							shutdown
						else
							@socket.send(JSON.generate({:event => "ready", :data => []}))
						end
					when :ping
						@socket.send(JSON.generate({:event => "pong", :data => []}))
					when :ls
						@socket.send(JSON.generate({:event => "ls",
							:data => Control::Communicator.system_list(@user)}))
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
					Control::System.logger.info "-- in html5.rb, recieve : invalid command received - #{data[:command]} --"
				end
			end
		}
	rescue => e
		logger = nil
		@data_lock.synchronize {
			logger = @system.nil? ? Control::System.logger : @system.logger
		}
		Control.print_error(logger, e, {
			:message => "in html5.rb, recieve : probably malformed JSON data",
			:level => Logger::ERROR
		})
	end
	
	def shutdown
		@socket.close_websocket
	end
	
	def notify(mod_sym, stat_sym, data)
		#
		# This should be re-entrant? So no need to protect
		#
		@system.logger.debug "#{mod_sym}.#{stat_sym} sent #{data.inspect}"
		@socket.send(JSON.generate({"event" => "#{mod_sym}.#{stat_sym}", "data" => data}))
	end
end


EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 81, :debug => true) do |socket|
	
	
	socket.onopen {
		#
		# This socket represents a connected device
		#
		id = socket
		
		EM.defer do
			begin
				HTML5Monitor.register(id)
				Control::System.logger.debug 'HTML5 browser connected'
			rescue => e
				Control.print_error(Control::System.logger, e, {
					:message => "in html5.rb, onopen in register : client could not be joined",
					:level => Logger::ERROR
				})
			end
		end
		
		socket.onmessage { |data|
			#
			# Attach socket here to system
			#	then process commands
			#
			EM.defer do
				begin
					HTML5Monitor.receive(id, data)
				rescue => e
					Control.print_error(Control::System.logger, e, {
						:message => "in html5.rb, onmessage : client did not exist (we may have been shutting down)",
						:level => Logger::ERROR
					})
				ensure
					ActiveRecord::Base.clear_active_connections!	# Clear any unused connections
				end
			end
		}

		socket.onclose {
			EM.defer do
				begin
					HTML5Monitor.unregister(id)
					Control::System.logger.debug "There are now #{HTML5Monitor.count} HTML5 clients connected"
				rescue => e
					Control.print_error(Control::System.logger, e, {
						:message => "in html5.rb, onclose : unregistering client did not exist (we may have been shutting down)",
						:level => Logger::ERROR
					})
				end
			end
		}
		
		socket.onerror { |error|
			if !error.kind_of?(EM::WebSocket::WebSocketError)
				EM.defer do
					Control.print_error(Control::System.logger, error, {
						:message => "in html5.rb, onerror : issue with websocket data",
						:level => Logger::ERROR
					})
				end
			else
				EM.defer do
					Control::System.logger.info "in html5.rb, onerror : invalid handshake received - #{error.inspect}"
				end
			end
		}
	}

end

Control::System.logger.info 'running HTML5 socket server on port 81'
