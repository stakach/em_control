#
# STD LIB
#
require 'observer'
require 'yaml'
require 'thread'


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

				@receive_lock = Mutex.new
				@send_lock = Mutex.new  # For in sync send and receives when required
				@wait_condition = ConditionVariable.new		# for waking and waiting on the revieve data
		
				@last_command = {}
				
				@is_connected = false
				@connect_retry = 0		# delay if a retry happens straight again

				#
				# Configure links between objects (This is a very loose tie)
				#
				@parent = Modules.last
				@parent.setbase(self)
			end
	
			attr_reader :is_connected
			attr_reader :default_send_options
			def default_send_options= (options)
				@default_send_options.merge!(options)
			end
			


			#
			# Using EM Queue which schedules tasks in order
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
				
				@send_queue.push(options)
				
				if @send_lock.locked?
					return
				end
				
				@send_lock.synchronize {		# Ensure queue order and queue sizes
					process_send
				}
			rescue
				#
				# save from bad user code (ie bad data)
				#	TODO:: add logger
				#
			end
	
	
			#
			# Function for user code
			#
			def last_command
				return @last_command[:data]
			end
			

			#
			# EM Callbacks: --------------------------------------------------------
			#
			def post_init
				return unless @parent.respond_to?(:initiate_session)
				operation = proc {
					begin
						@parent.initiate_session
					rescue
						#
						# save from bad user code (don't want to deplete thread pool)
						#	TODO:: add logger
						#
					end
				}
				EM.defer(operation)
			end

	
			def connection_completed
				# set status
				
				resume if paused?
				@last_command[:wait] = false if !@last_command[:wait].nil?	# re-start event process
				@connect_retry = 0
				@is_connected = true
				
				return unless @parent.respond_to?(:connected)
				operation = proc {
					begin
						@parent.connected
					rescue
						#
						# save from bad user code (don't want to deplete thread pool)
						#	TODO:: add logger
						#
					end
				}
				EM.defer(operation)
			end

  
			def receive_data(data)
				@receive_lock.synchronize {
					@receive_queue.push(data)

					if @send_lock.locked?
						begin
							@timeout.cancel	# incase the timer is not active or nil
						rescue
						end
						@wait_condition.signal		# signal the thread to wakeup
					else
						operation = proc { self.process_data }
						EM.defer(operation)
					end
				}
			end


			def unbind
				# set offline
				@is_connected = false				

				operation = proc {
					begin
						@parent.disconnected
					rescue
						#
						# save from bad user code (don't want to deplete thread pool)
						#	TODO:: add logger
						#
					end
				}
				EM.defer(operation) if @parent.respond_to?(:disconnected)
				
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
			

			private


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
			def attempt_retry
				if @send_queue.empty? && @last_command[:retries] > 0	# no user defined replacements
					@last_command[:retries] -= 1
					@send_queue.push(@last_command)
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
					data = @send_queue.pop(true)
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
				end while not @send_queue.empty?
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
								p value		# the print command
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
									end
								end
								Modules.connections[device] = [ip, port]
								EM.connect ip, port, Device::Base
							end
						when :controllers
							
					end
				end
			end

			#devices = Devices.new
			#devices << NECProj.new
			#devices[:projector1] = Devices.last
			#Devices.connections[Devices.last] = ["127.0.0.1", 8081]
			#EM.connect "127.0.0.1", 8081, Device::Base
			require './interfaces/telnet/telnet.rb'
			TelnetServer.start
		end
	end
end



#
# Will be controlled in our launch program
#

Control.start
