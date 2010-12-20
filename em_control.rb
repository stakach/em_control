#
# STD LIB
#
require 'observer'
require 'yaml'
require 'thread'
require 'monitor'


#
# Gems
#
require 'rubygems'
require 'eventmachine'
require 'active_support'
require 'active_support/core_ext/string'


#
# Library Files
#
require './constants.rb'
require './utilities.rb'
require './modules.rb'
require './status.rb'
require './device.rb'
require './logic.rb'
require './interfaces/communicator.rb'
require './interfaces/deferred.rb'
require './system.rb'


module Control
	class Device
	

		#
		# This is how sending works
		#		Send recieves data, turns a mutex on and sends the data
		#			-- It goes into the recieve mutex critical section and sleeps waiting for a response
		#			-- a timeout is used as a backup in case no response is recieved
		#		The recieve function does the following
		#			-- If the send lock is not active it processes the recieved data
		#			-- otherwise it notifies the send function that data is avaliable
		#
		class Base < EventMachine::Connection
			include Utilities
			
			def initialize *args
				super
		
				@default_send_options = {	
					:wait => true,
					:max_waits => 3,
					:retries => 2,
					:hex_string => false,
					:timeout => 5
				}

				@receive_queue = Queue.new
				@send_queue = Queue.new
				@pri_queue = Queue.new
				@pri_queue.extend(MonitorMixin)

				@receive_lock = Mutex.new
				@send_lock = Mutex.new  # For in sync send and receives when required
				@critical_lock = Mutex.new
				@wait_condition = ConditionVariable.new		# for waking and waiting on the revieve data
		
				@last_command = {}
				
				@is_connected = false
				@connect_retry = 0		# delay if a retry happens straight again

				#
				# Configure links between objects (This is a very loose tie)
				#	Relies on serial loading of modules
				#
				@parent = Modules.last
				@parent.setbase(self)
				@tls_enabled = Modules.connections[@parent][2]
			end
	
			attr_reader :is_connected
			attr_reader :default_send_options
			def default_send_options= (options)
				@default_send_options.merge!(options)
			end
			


			#
			# Using EM Queue which schedules tasks in order
			#	Returns false if command queued (for execution on another thread)
			#	True if processed on this thread
			#
			def send(data, options = {})
				if !@is_connected
					return					# do not send when not connected
				end
					
				options = @default_send_options.merge(options)
					
				#
				# Make sure we are sending appropriately formatted data
				#
				if data.class == Array
					data = array_to_str(data)
				elsif options[:hex_string] == true
					data = hex_to_byte(data)
				end

				options[:data] = data
				options[:retries] = 0 if options[:wait] == false
				
				
				#
				# Use a monitor here to allow for re-entrant locking
				#	This will allow for a priority queue and then we guarentee order of operations
				#
				@critical_lock.lock

				if @send_lock.locked?
					@critical_lock.unlock

					if @pri_queue.mon_try_enter		# Does this thread own the send_lock?
						@pri_queue.push(options)
						@pri_queue.mon_exit
					else
						@send_queue.push(options)	# If not then it must be another thread
					end
					return false
				else
					@send_queue.push(options)
				end
				
				@send_lock.synchronize {		# Ensure queue order and queue sizes
					@pri_queue.synchronize do
						process_send			# NOTE::critical lock is released in process send
					end
				}
				@critical_lock.unlock			# NOTE::Locked in process send so requires unlocking here
				
				return true
			rescue => e
				#
				# save from bad user code (ie bad data)
				#	TODO:: add logger
				#
				@critical_lock.unlock			# Just in case
				p e.message
				p e.backtrace
				return true
			end
	
	
			#
			# Function for user code
			#
			def last_command
				return str_to_array(@last_command[:data])
			end
			

			#
			# EM Callbacks: --------------------------------------------------------
			#
			def post_init
				start_tls if @tls_enabled								# If we are using tls or ssl
				return unless @parent.respond_to?(:initiate_session)
				
				begin
					@parent.initiate_session(@tls_enabled)
				rescue
					#
					# save from bad user code (don't want to deplete thread pool)
					#	TODO:: add logger
					#
				end
			end
			

			def ssl_handshake_completed
				call_connected				# this will mark the true connection complete stage for encrypted devices
			end

	
			def connection_completed
				# set status
				
				resume if paused?
				@last_command[:wait] = false if !@last_command[:wait].nil?	# re-start event process
				@connect_retry = 0
				
				if !@tls_enabled
					call_connected
				end
			end

  
			def receive_data(data)
				@receive_queue.push(data)
				
				EM.defer do
					@receive_lock.synchronize {
						if @send_lock.locked?
							begin
								@timeout.cancel	# incase the timer is not active or nil
							rescue
							end
							@wait_condition.signal		# signal the thread to wakeup
						else
							self.process_data
						end
					}
				end
			end


			def unbind
				# set offline
				@is_connected = false				

				if @parent.respond_to?(:disconnected)
					EM.defer do
						begin
							@parent.disconnected
						rescue
							#
							# save from bad user code (don't want to deplete thread pool)
							#	TODO:: add logger
							#
						end
					end
				end
				
				# attempt re-connect
				#	if !make and break
				settings = Modules.connections[@parent]
				
				if @connect_retry == 0
					reconnect settings[0], settings[1]
					@connect_retry = 1
				else
					@connect_retry += 1
					#
					# TODO - log this at least once
					#	if @connect_retry == 2
					#
					EM.add_timer 5, proc { 
						reconnect settings[0], settings[1]
					}
				end
			end
			#
			# ----------------------------------------------------------------------
			#
			

			#private


			#
			# Controls the flow of data for retry puropses
			#
			def process_data
				if @parent.respond_to?(:received)
					return @parent.received(str_to_array(@receive_queue.pop(true)))	# non-blocking call (will crash if there is no data)
				else	# If no receive function is defined process the next command
					@receive_queue.pop(true)
					return true
				end
			rescue => e
				#
				# save from bad user code (don't want to deplete thread pool)
				#	This error should be logged in some consistent manner
				#	TODO:: Create logger
				#
				p e.message
				p e.backtrace
				return true
			end
	
	
			#
			# Ready state for next attempt
			#	WARN:: Must be called in send_lock critical section
			#
			#	A return false will always retry the command at the end of the queue
			#
			def attempt_retry
				if @pri_queue.empty? && @last_command[:retries] > 0	# no user defined replacements
					@last_command[:retries] -= 1
					@pri_queue.push(@last_command)
				end
			end
			
			def wait_response
				@receive_lock.synchronize {
					if @receive_queue.empty?
						@timeout = EventMachine::Timer.new(@last_command[:timeout]) do 
							@receive_lock.synchronize {
								@wait_condition.signal		# wake up the thread
							}
							#
							# TODO:: log the event here
							#	EM.defer(proc {log_issue})	# lets not waste time in this thread
							#
						end
						@wait_condition.wait(@receive_lock)
					end
				}
			end
			
			def process_response
				num_rets = @last_command[:max_waits]
				begin
					wait_response
						
					if not @receive_queue.empty?
						response = process_data
						if response == false
							attempt_retry
							return
						elsif response == true
							return
						end
					else	# the wait timeout occured - retry command
						attempt_retry
						return
					end

					#
					# If we haven't returned before we reach this point then the last data was
					#	not relavent and we are still waiting (max wait == num_retries * timeout)
					#
					num_rets -= 1
				end while num_rets > 0
			end

			#
			# Send data
			#	WARN:: Must be called in send_lock critical section
			#
			def process_send
				begin
					@critical_lock.unlock
					if @pri_queue.empty?
						data = @send_queue.pop(true)
					else
						data = @pri_queue.pop(true)
					end
					
					@last_command = data
					
					EM.schedule proc {
						begin
							if !error?
								send_data(data[:data])
							end
						rescue
							#
							# Save the thread in case of bad data in that send
							#
						end
					}
				
					#
					#	Synchronize the response
					#
					if data[:wait]
							process_response
					end
					@critical_lock.lock
				end while !@send_queue.empty? || !@pri_queue.empty?
			end
			

			private
			

			def call_connected
				@is_connected = true
				
				return unless @parent.respond_to?(:connected)

				EM.defer do
					begin
						@parent.connected
					rescue
						#
						# save from bad user code (don't want to deplete thread pool)
						#	TODO:: add logger
						#
					end
				end
			end
		end
	end
	
	#
	# Load the config file and start the modules
	#
	def self.start
		EventMachine.run do
			require 'yaml'
			settings = YAML::load_file 'settings.yml'
			settings.each do |name, room|
				system = System.new(name.to_sym)
				room.each do |settings, mod_name|
					case settings.to_sym
						when :devices
							mod_name.each do |key, value|
								require "./devices/#{key}.rb"
								device = key.classify.constantize.new
								system.modules << device
								ip = nil
								port = nil
								tls = false
								p value		# TODO:: Log the command
								value.each do |field, data|
									case field.to_sym
										when :names
											symdata = []
											data.each {|item|
												item = item.to_sym
												system.modules[item] = device
												symdata << item
											}
											system.modules[device] = symdata
										when :ip
											ip = data
										when :port
											port = data.to_i
										when :tls
											tls = !(/^true$/i =~ data).nil?
									end
								end
								Modules.connections[device] = [ip, port, tls]
								EM.connect ip, port, Device::Base
							end
						when :controllers
							mod_name.each do |key, value|
								require "./controllers/#{key}.rb"
								control = key.classify.constantize.new(system)
								system.modules << control
								p value		# TODO:: Log the command
								value.each do |field, data|
									case field.to_sym
										when :names
											symdata = []
											data.each {|item|
												item = item.to_sym
												system.modules[item] = device
												symdata << item
											}
											system.modules[device] = symdata
									end
								end
							end
					end
				end
			end

			#devices = Devices.new
			#devices << NECProj.new
			#devices[:projector1] = Devices.last
			#Devices.connections[Devices.last] = ["127.0.0.1", 8081]
			#EM.connect "127.0.0.1", 8081, Device::Base
			

			#
			# AutoLoad the interfaces
			#
			require './interfaces/telnet/telnet.rb'
			TelnetServer.start
			require './interfaces/html5/html5.rb'
		end
	end
end



#
# Will be controlled in our launch program
#

Control.start
