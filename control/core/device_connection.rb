module Control

	#
	# This contains the basic constructs required for
	#	serialised comms over TCP and UDP
	#
	module DeviceConnection
		def initialize *args
			super
		
			@default_send_options = {	
				:wait => true,
				:max_waits => 3,
				:retries => 2,
				:hex_string => false,
				:timeout => 5,
				:priority => 0
			}

			@receive_queue = Queue.new	# So we can process responses in different ways
			@task_queue = Queue.new		# basically we add tasks here that we want to run in a strict order
			
			@dummy_queue = Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
			@pri_queue = PriorityQueue.new		# high priority
			@send_queue = PriorityQueue.new		# regular priority
			@send_queue.extend(MonitorMixin)

			@receive_lock = Mutex.new	# Recieve data communications
			@send_lock = Mutex.new		# For in sync send and receives when required

			@wait_condition = ConditionVariable.new			# for waking and waiting on the revieve data
			@connected_condition = ConditionVariable.new		# for maintaining the current queue on disconnect and re-starting
		
				
			@status_lock = Mutex.new	# A lock for last command and is_connected
			@last_command = {}		# The last command sent
			@is_connected = false
			@connect_retry = 0		# Required by control_base (unbind)

			#
			# Configure links between objects (This is a very loose tie)
			#	Relies on serial loading of modules
			#
			@parent = Modules.loading
			@parent.setbase(self)
			@logger = @parent.logger
			@tls_enabled = DeviceModule.lookup[@parent].tls
				
			#
			# Task event loop
			#	TODO:: Shutdown flag
			#
			EM.defer do
				while true
					begin
						task = @task_queue.pop
						task.call
					rescue => e
						@logger.error "-- module #{@parent.class} in em_control.rb, base : error in task loop --"
						@logger.error e.message
						@logger.error e.backtrace
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
				
			#
			# Send event loop
			#
			EM.defer do
				@send_queue.synchronize do	# this thread is the send queue (so we lock it)
					data = nil
					while true
						begin
							@dummy_queue.pop
						
							if @pri_queue.empty?
								data = @send_queue.pop
							else
								data = @pri_queue.pop
							end
							@send_lock.synchronize {
								process_send(data)
							}
						rescue => e
							@logger.error "-- module #{@parent.class} in em_control.rb, base : error in send loop --"
							@logger.error e.message
							@logger.error e.backtrace
						ensure
							ActiveRecord::Base.clear_active_connections!
						end
					end
				end
			end
			
			#
			# Recieve event loop
			#
			EM.defer do
				while true
					begin
						data = @receive_queue.pop
						@receive_lock.lock
						if @send_lock.locked?
							@status_lock.synchronize {
								@last_command[:response] = data
							}
							@wait_condition.signal		# signal the thread to wakeup
							@receive_lock.unlock
						else
							#
							# requires all the send locks ect to prevent recursive locks
							#	and avoid any errors (these would have been otherwise set during a send)
							#
							@receive_lock.unlock
							@send_lock.synchronize {
								self.process_data(data)
							}
						end
					rescue => e
						@logger.error "-- module #{@parent.class} in em_control.rb, base : error in recieve loop --"
						@logger.error e.message
						@logger.error e.backtrace
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
		end
			

		attr_reader :is_connected
		attr_reader :default_send_options
		def default_send_options= (options)
			@default_send_options.merge!(options)
		end
			


		#
		# Processes sends in strict order
		#
		def send(data, options = {})
			
			begin
				@status_lock.synchronize {
					if !@is_connected
						return true
					end
				}


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
			rescue => e
				@logger.error "-- module #{@parent.class} in em_control.rb, send : possible bad data or options hash --"
				@logger.error e.message
				@logger.error e.backtrace
					
				return true
			end
				
				
			#
			# Use a monitor here to allow for re-entrant locking
			#	This allows for a priority queue and we guarentee order of operations
			#
			#	See Device::send for why we are locking here
			#
			if !options[:emit].nil?
				@parent.status_lock.lock
			end

			if @send_queue.mon_try_enter			# is this the same thread?
				@pri_queue.push(options, options[:priority])		# Prioritise the command
				@send_queue.mon_exit
			else
				@send_queue.push(options, options[:priority])
			end
			@dummy_queue.push(nil)	# informs our send loop that we are ready
				
			return false
		rescue => e
			#
			# Save from a fatal error
			#
			if @parent.status_lock.locked?
				@parent.status_lock.unlock
			end
			@logger.error "-- module #{@parent.class} in em_control.rb, send : something went terribly wrong to get here --"
			@logger.error e.message
			@logger.error e.backtrace
			return true
		end
	
	
		#
		# Function for user code
		#	last command protected by send lock
		#
		def last_command
			@status_lock.synchronize {
				return str_to_array(@last_command[:data])
			}
		end
		
		def call_connected
			@status_lock.synchronize {
				@is_connected = true
			}
				
			@send_lock.synchronize {
				@connected_condition.signal		# wake up the thread
			}
			
			@task_queue.push lambda {
				@parent[:connected] = true
				return unless @parent.respond_to?(:connected)
				begin
					@parent.connected
				rescue => e
					#
					# save from bad user code (don't want to deplete thread pool)
					#
					@logger.error "-- module #{@parent.class} error whilst calling: connect --"
					@logger.error e.message
					@logger.error e.backtrace
				end
			}
		end
		
		def do_receive_data(data)
			@receive_queue.push(data)	# For processing on the send queue if the thread is locked
		end
		
		#
		# Controls the flow of data for retry puropses
		#
		def process_data(data)
			if @parent.respond_to?(:received)
				return @parent.received(str_to_array(data))	# non-blocking call (will throw an error if there is no data)
			else	# If no receive function is defined process the next command
				return true
			end
		rescue => e
			#
			# save from bad user code (don't want to deplete thread pool)
			#	This error should be logged in some consistent manner
			#
			@logger.error "-- module #{@parent.class} error whilst calling: received --"
			@logger.error e.message
			@logger.error e.backtrace
				
			return true
		end

		#
		# Send data
		#	send_lock is active
		#	send_queue monitor is active
		#
		def process_send(data)
			@status_lock.lock
			@last_command = data
			if @is_connected == false
				@status_lock.unlock
				@connected_condition.wait(@send_lock)
			else
				@status_lock.unlock
			end

			@receive_lock.synchronize {
				EM.schedule proc {	# Send data on the reactor thread
					begin
						if !error?
							do_send_data(data[:data])
						end
					rescue => e
						#
						# Save the thread in case of bad data in that send
						#
						EM.defer do
							@logger.error "-- module #{@parent.class} in em_control.rb, process_send : possible bad data --"
							@logger.error e.message
							@logger.error e.backtrace
						end
					end
				}
				
				#
				# Synchronize the response
				#
				if data[:wait]
					wait_response
				end
			}
		end
			

		def wait_response
			num_rets = nil
			timeout = nil
			@status_lock.synchronize {
				num_rets = @last_command[:max_waits]
				timeout = @last_command[:timeout]
			}
			begin
				@wait_condition.wait(@receive_lock, timeout)
				
				data = nil
				@status_lock.synchronize {
					data = @last_command.delete(:response)
				}
				if data.nil?	# The wait timeout occured - retry command
					@logger.debug "-- module #{@parent.class} in em_control.rb, wait_response --"
					@logger.debug "A response was not recieved for the current command"
					attempt_retry
					return
				else					# Process the data
					response = process_data(data)
					if response == false
						attempt_retry
						return
					elsif response == true
						return
					end
				end
				#
				# If we haven't returned before we reach this point then the last data was
				#	not relavent and we are still waiting (max wait == num_retries * timeout)
				#
				num_rets -= 1
			end while num_rets > 0
		end
		
		def attempt_retry
			@status_lock.lock		# for last_command
			if @pri_queue.empty? && @last_command[:retries] > 0	# no user defined replacements and retries left
				@last_command[:retries] -= 1
				@pri_queue.push(@last_command)
				@status_lock.unlock
				@dummy_queue.push(nil)	# informs our send loop that we are ready
			else
				@status_lock.unlock
			end
		end
	end

end