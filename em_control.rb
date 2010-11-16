#
# Gems
#
require 'rubygems'
require 'eventmachine'
require 'algorithms'
require 'yaml'
require 'active_support'
require 'active_support/core_ext/string'


#
# Library Files
#
require './devices.rb'
require './device.rb'
require './controller.rb'

module Control
	class Device
		class Base < EventMachine::Connection

			def initialize *args
				super
		
				@default_send_options = {	
					:priority => 0,
					:wait => true,
					:retries => 2
				}

				@recieve_queue = Queue.new

				@recieve_lock = Mutex.new
				@send_lock = Mutex.new  # For in sync send and recieves when required
		
				@send_queue = Containers::PriorityQueue.new
				@last_command = {}
				
				@is_connected = false
				@connect_retry = 0		# delay if a retry happens straight again

				#
				# Configure links between objects
				#
				@parent = Devices.last
				@parent.setbase(self)
			end
	
			attr_reader :is_connected
			attr_reader :default_send_options
			def default_send_options= (options)
				@default_send_options.merge!(options)
			end


			#
			# EM Callbacks: --------------------------------------------------------
			#
			def post_init
				
			end

	
			def connection_completed
				# set status
				
				resume if paused?
				@last_command[:wait] = false if !@last_command[:wait].nil?	# re-start event process
				@connect_retry = 0
				@is_connected = true
				operation = proc { @parent.connected }
				EM.defer(operation) if @parent.respond_to?(:connected)
			end

  
			def receive_data(data)
				@recieve_queue.push(data)

				operation = proc { self.process_data }
				EM.defer(operation)
			end


			def unbind
				# set offline
				@is_connected = false				

				operation = proc { @parent.disconnected }
				EM.defer(operation) if @parent.respond_to?(:disconnected)
				
				# attempt re-connect
				#	if !make and break
				settings = Devices.connections[@parent]
				
				if @connect_retry == 0
					reconnect settings[0], settings[1]
					@connect_retry = 1
				else
					EM.add_timer 5, proc { 
						reconnect settings[0], settings[1]
					}
				end
			end
			#
			# ----------------------------------------------------------------------
			#


			#
			# Using EM Queue which schedules tasks in order
			#
			def send(data, options = {})
				@send_lock.synchronize {		# Ensure queue order and queue sizes
				
					if !@is_connected
						return		# do not send when not connected
					end

					options = @default_send_options.merge(options)
					options[:data] = data
					options[:retries] = 0 if options[:wait] == false
					@send_queue.push(options, options[:priority])
			
					waitingResponse = @last_command[:wait] == true	# must do this incase :wait == nil
			
					if !waitingResponse
						@last_command = options
						process_send
					end
				}
			end
	
	
			#
			# Function for user code
			#
			def last_command
				return @last_command[:data]
			end


			protected


			#
			# Controls the flow of data for retry puropses
			#
			def process_data
				@recieve_lock.synchronize {			# Lock ensures that serialisation of events per-device module
				
					succeeded = nil
					if @parent.respond_to?(:recieved)
		
						succeeded = @parent.recieved(@recieve_queue.pop(true))	# non-blocking call (will crash if there is no data)

						@send_lock.synchronize {		# recieved call can call send so must sync here
							if succeeded == false
								if @send_queue.has_priority?(@last_command[:priority] + 1) == false && @last_command[:retries] > 0	# no user defined replacements
									@last_command[:retries] -= 1
									@send_queue.push(@last_command, @last_command[:priority] + 1)
							
									process_send
								elsif @send_queue.has_priority?(@last_command[:priority] + 1) == false	# user defined replacement for retry
									process_send
								else
									next_command	# give up and continue processing
								end
							elsif succeeded == true
								next_command		# success so continue processing
							end
						}
					
					#
					# If no recieve function is defined process the next command
					#
					else
						@recieve_queue.pop(true)	# this is thread safe
						@send_lock.synchronize {
							next_command
						}
					end
				}
			end


			private
	
	
			#
			# Ready state for next command
			#	WARN:: Must be called in send_lock critical section
			#
			def next_command
				if @send_queue.size > 0
					process_send
				else
					@last_command[:wait] = false
				end
			end

			#
			# Send data
			#	WARN:: Must be called in send_lock critical section
			#
			def process_send
				data = @send_queue.pop
				@last_command = data

				EM.schedule proc {
					if !error?
						send_data(data[:data])
					end
				}
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
				controller = Controller.new(name, Devices.new)
				room.each do |settings, mod_name|
					case settings.to_sym
						when :devices
							mod_name.each do |key, value|
								require "./devices/#{key}.rb"
								device = key.classify.constantize.new
								controller.devices << device
								ip = nil
								port = nil
								p value
								value.each do |field, data|
									case field.to_sym
										when :names
											data.each {|item| controller.devices[item.to_sym] = device}
										when :ip
											ip = data
										when :port
											port = data.to_i
									end
								end
								Devices.connections[device] = [ip, port]
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
		end
	end
end



#
# Will be controlled in our launch program
#

Control.start
