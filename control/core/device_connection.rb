#
# This contains the basic constructs required for
#	serialised comms over TCP and UDP
#
module Control

	
	module DeviceConnection
		def shutdown(system)
			if @parent.leave_system(system) == 0
				@shutting_down = true
				
				close_connection
				@dummy_queue.push(nil)
				@task_queue.push(nil)
				@receive_queue.push(nil)
				
				EM.defer do
					@parent[:connected] = false
					if @parent.respond_to?(:disconnected)
						begin
							@parent.disconnected
						rescue => e
							#
							# save from bad user code (don't want to deplete thread pool)
							#
							logger.error "-- module #{@parent.class} error whilst calling: disconnected --"
							logger.error e.message
							logger.error e.backtrace
						end
					end
				end
			end
		end
		
		
		def initialize *args
			super
		
			@default_send_options = {
				:wait => true,			# Wait for response
				:delay => 0,			# Delay next send by x.y seconds
				:max_waits => 3,
				:retries => 2,
				:hex_string => false,
				:timeout => 5,			# Timeout in seconds
				:priority => 0,
				:max_buffer => 1048576	# 1mb
			}

			@receive_queue = Queue.new	# So we can process responses in different ways
			@data_packet = nil
			@task_queue = Queue.new		# basically we add tasks here that we want to run in a strict order
			
			@dummy_queue = Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
			@pri_queue = PriorityQueue.new		# high priority
			@send_queue = PriorityQueue.new		# regular priority
			@send_queue.extend(MonitorMixin)
			@last_send_at = 0.0

			@receive_lock = Mutex.new	# Recieve data communications
			@send_lock = Mutex.new		# For in sync send and receives when required
			@confirm_send_lock = Mutex.new		# For use in confirming when a send has taken place

			@wait_condition = ConditionVariable.new			# for waking and waiting on the recieve data
			@connected_condition = ConditionVariable.new	# for maintaining the current queue on disconnect and re-starting
			@sent_condition = ConditionVariable.new			# This is used to confirm the send
		
				
			@status_lock = Mutex.new	# A lock for last command and is_connected
			@last_command = {}		# The last command sent
			@is_connected = false
			@connect_retry = 0		# Required by control_base (unbind)

			#
			# Configure links between objects (This is a very loose tie)
			#	Relies on serial loading of modules
			#
			@parent = Modules.loading[0]
			@parent.setbase(self)
			@tls_enabled = @parent.secure_connection
			@shutting_down = false
			
			#
			# Task event loops
			#
			EM.defer do
				while true
					begin
						task = @task_queue.pop
						break if @shutting_down
						
						task.call
					rescue => e
						logger.error "module #{@parent.class} in device_connection.rb, base : error in task loop --"
						logger.error e.message
						logger.error e.backtrace
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
					waitRequired = false
					delay = 0.0
					while true
						begin
							@dummy_queue.pop
							break if @shutting_down
						
							if @pri_queue.empty?
								data = @send_queue.pop
							else
								data = @pri_queue.pop
							end
							
							#
							# Guarantee minimum delays between sends
							#
							if waitRequired
								waitRequired = false
								delay = @last_send_at + delay - Time.now.to_f
								delay = 0.0 unless delay > 0.0
							else
								delay = 0.0
							end
							doDelay = delay
							if data[:delay] != 0
								waitRequired = true
								delay = data[:delay].to_f
							end
							
							#
							# Process the sending of the command (and response if we are waiting)
							#
							@send_lock.synchronize {
								process_send(data, doDelay)
							}
						rescue => e
							logger.error "module #{@parent.class} in device_connection.rb, base : error in send loop --"
							logger.error e.message
							logger.error e.backtrace
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
						break if @shutting_down
						
						@receive_lock.lock
						if @send_lock.locked?
							@data_packet = data
							@wait_condition.broadcast		# signal the thread to wakeup
							@wait_condition.wait(@receive_lock)
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
						begin
							@receive_lock.unlock
						rescue
						end
						logger.error "module #{@parent.class} in device_connection.rb, base : error in recieve loop --"
						logger.error e.message
						logger.error e.backtrace
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
		end
			

		attr_reader :is_connected
		attr_reader :default_send_options
		def default_send_options= (options)
			@status_lock.synchronize {
				@default_send_options.merge!(options)
			}
		end
			
		
		def logger
			@parent.logger
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
					
					options = @default_send_options.merge(options)
				}
					
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
				logger.error "module #{@parent.class} in device_connection.rb, send : possible bad data or options hash --"
				logger.error e.message
				logger.error e.backtrace
					
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
			logger.error "module #{@parent.class} in device_connection.rb, send : something went terribly wrong to get here --"
			logger.error e.message
			logger.error e.backtrace
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
		
		def call_connected(*args)
			@status_lock.synchronize {
				@is_connected = true
			}
				
			@send_lock.synchronize {
				@connected_condition.broadcast		# wake up the thread
			}
			
			#
			# Same as add parent!!!
			#
			@task_queue.push lambda {
				@parent[:connected] = true
				return unless @parent.respond_to?(:connected)
				begin
					@parent.connected(*args)
				rescue => e
					#
					# save from bad user code (don't want to deplete thread pool)
					#
					logger.error "module #{@parent.class} error whilst calling: connect --"
					logger.error e.message
					logger.error e.backtrace
				end
			}
		end
		
		#
		# Data recieved
		#	Allow modules to set message delimiters for auto-buffering
		#	Default max buffer length == 1mb (setting can be overwritten)
		#	NOTE: The buffer cannot be defered otherwise there are concurrency issues 
		#
		def do_receive_data(data)
			if @parent.respond_to?(:response_delimiter)
				begin
					@buf ||= BufferedTokenizer.new(build_delimiter, @default_send_options[:max_buffer])    # Call back for character
					result = @buf.extract(data)
					EM.defer do
						result.each do |line|
							@receive_queue.push(line)
						end
					end
					return	# Prevent fall through (on error we will add the data to the recieve queue)
				rescue => e
					@buf = nil	# clear the buffer
					EM.defer do
						logger.error "module #{@parent.class} error whilst setting delimiter --"
						logger.error e.message
						logger.error e.backtrace
					end
				end
			end
				
			EM.defer do
				@receive_queue.push(data)
			end
		end
		
		def build_delimiter
			#
			# Delimiter can be a byte array, string or regular expression
			#
			del = @parent.response_delimiter
			if del.class == Array
				del = array_to_str(del)
			elsif del.class == Fixnum
				del = "" << del #array_to_str([del & 0xFF])
			end
			
			return del
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
			logger.error "module #{@parent.class} error whilst calling: received --"
			logger.error e.message
			logger.error e.backtrace
				
			return true
		end

		#
		# Send data
		#	send_lock is active
		#	send_queue monitor is active
		#
		def process_send(data, delay)
			@status_lock.lock		# Status locked
			@last_command = data
			if @is_connected == false
				@status_lock.unlock
				@connected_condition.wait(@send_lock)
			else
				@status_lock.unlock
			end
			
			process = proc {
				begin
					if !error?
						do_send_data(data[:data])
					end
				rescue => e
					#
					# Save the thread in case of bad data in that send
					#
					EM.defer do
						logger.error "module #{@parent.class} in device_connection.rb, process_send : possible bad data --"
						logger.error e.message
						logger.error e.backtrace
					end
				ensure
					#
					# Trigger last sent here (defered to prevent locking on reactor)
					#
					@last_send_at = Time.now.to_f
					EM.defer do
						@confirm_send_lock.synchronize {
							@sent_condition.broadcast
						}
					end
				end
			}
			
			@receive_lock.synchronize {
				@confirm_send_lock.synchronize {
					#
					# Provides non-blocking delays on data being sent
					# 	The delay may be longer than specified, never shorter.
					#
					if delay == 0.0
						EM.schedule process	# Send data on the reactor thread
					else
						EM.add_timer delay, process
					end
					@sent_condition.wait(@confirm_send_lock)	# This ensures we know when any data was sent
					
					
					#
					# Synchronize the response
					#
					if data[:wait]
						begin
							wait_response
						ensure
							@wait_condition.broadcast	# The datapacket is free for overwriting
						end
					end
				}
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
				
				if @data_packet.nil?	# The wait timeout occured - retry command
					logger.debug "module #{@parent.class} in device_connection.rb, wait_response"
					logger.debug "A response was not recieved for the current command"
					attempt_retry
					return
				else					# Process the data
					response = process_data(@data_packet)
					@data_packet = nil
					
					if response == false
						attempt_retry
						return
					elsif response == true
						return
					end
					
					@wait_condition.broadcast	# A nil response (we need the next data)
				end
				#
				# If we haven't returned before we reach this point then the last data was
				#	not relavent or complete (framing) and we are still waiting (max wait == num_retries * timeout)
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