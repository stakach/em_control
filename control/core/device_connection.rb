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
					@parent.clear_emit_waits
					if @parent.respond_to?(:disconnected)
						begin
							@task_lock.synchronize {
								@parent.disconnected
							}
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
				:delay_on_recieve => 0,	# Delay next send after a recieve by x.y seconds (only works when we are waiting for responses)
				:max_waits => 3,
				:retries => 2,
				:hex_string => false,
				:timeout => 5,			# Timeout in seconds
				:priority => 0,
				:max_buffer => 1048576	# 1mb, probably overkill for a defualt
			}

			@receive_queue = Queue.new	# So we can process responses in different ways
			@data_packet = nil
			@task_queue = Queue.new		# basically we add tasks here that we want to run in a strict order
			
			@dummy_queue = Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
			@pri_queue = PriorityQueue.new		# high priority
			@send_queue = PriorityQueue.new		# regular priority
			@send_queue.extend(MonitorMixin)
			@last_send_at = 0.0
			@last_recieve_at = 0.0

			@task_lock = Mutex.new		# Make sure no task processes are being executed
			@receive_lock = Mutex.new	# Recieve data communications
			@send_lock = Mutex.new		# For in sync send and receives when required
			@confirm_send_lock = Mutex.new		# For use in confirming when a send has taken place

			@wait_condition = ConditionVariable.new			# for waking and waiting on the recieve data
			@connected_condition = ConditionVariable.new	# for maintaining the current queue on disconnect and re-starting
			@sent_condition = ConditionVariable.new			# This is used to confirm the send
			
			
			@response_lock = Mutex.new
			@response_condition = ConditionVariable.new
		
				
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
						
						@task_lock.synchronize {
							task.call
						}
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
								@status_lock.synchronize {
									@last_command = {:data => data}
								}
								@response_lock.synchronize {
									EM.defer do
										logger.debug "Out of order response recieved from #{@parent.class}"
										begin
											@send_queue.mon_enter	# this indicates the priority send queue
											process_data(data)
										ensure
											@send_queue.mon_exit
										end
									end
									@response_condition.wait(@response_lock)
									
									response = @process_data_result
								}
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
		attr_reader :send_queue
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
		
		def command_option(key)
			@status_lock.synchronize {
				return @last_command[key]
			}
		end
		
		
		def call_connected(*args)		# Called from a deferred thread
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
			recieve_at = Time.now.to_f
			
			if @parent.respond_to?(:response_delimiter)
				begin
					@buf ||= BufferedTokenizer.new(build_delimiter, @default_send_options[:max_buffer])    # Call back for character
					result = @buf.extract(data)
					EM.defer do
						@status_lock.synchronize {
							@last_recieve_at = recieve_at
						}
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
				@status_lock.synchronize {
					@last_recieve_at = recieve_at
				}
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
			this = 0
			@response_lock.synchronize {
				@process_data_result = nil
				@process_data_id = @process_data_id || 0
				@process_data_id = 1 if @process_data_id > 999999
				this = @process_data_id
			}
			result = :fail
			begin
				if @parent.respond_to?(:received)
					result = @parent.received(str_to_array(data))	# non-blocking call (will throw an error if there is no data)
				else	# If no receive function is defined process the next command
					result = true
				end
			rescue => e
				#
				# save from bad user code (don't want to deplete thread pool)
				#	This error should be logged in some consistent manner
				#
				logger.error "module #{@parent.class} error whilst calling: received --"
				logger.error e.message
				logger.error e.backtrace
			end
			@response_lock.synchronize {
				if this == @process_data_id
					@process_data_id += 1
					@process_data_result = result
					@response_condition.broadcast
				end
			}
		end
		
		
		def process_data_result(result)	# called from user code
			@response_lock.synchronize {
				@process_data_id += 1
				@process_data_result = result
				@response_condition.broadcast
			}
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
			
			if data[:delay_on_recieve] > 0.0
				@status_lock.synchronize {
					retdelay = @last_recieve_at + data[:delay_on_recieve] - Time.now.to_f
					sleep(retdelay) if retdelay > 0.0
				}
			end
		end
			

		def wait_response
			num_rets = nil
			timeout = nil
			emit = nil
			@status_lock.synchronize {
				num_rets = @last_command[:max_waits]
				timeout = @last_command[:timeout]
				emit = @last_command[:emit]
			}
			
			while true
				@wait_condition.wait(@receive_lock, timeout)
				
				if @data_packet.nil?	# The wait timeout occured - retry command
					logger.debug "module #{@parent.class} in device_connection.rb, wait_response"
					logger.debug "A response was not recieved for the current command"
					attempt_retry(emit)
					return
				else					# Process the data
					response = nil
					
					
					@response_lock.synchronize {
						EM.defer do
							begin
								@send_queue.mon_enter	# this indicates the priority send queue
								process_data(@data_packet)
							ensure
								@send_queue.mon_exit
							end
						end
						@response_condition.wait(@response_lock)
						
						response = @process_data_result
					}
					
					@data_packet = nil
					
					if response == false
						attempt_retry(emit)
						return
					elsif response == true
						return
						#
						# Up to the user to ensure any emit is triggered when returning true!
						#
					elsif response == :fail
						num_rets = 1
					end
				end
				#
				# If we haven't returned before we reach this point then the last data was
				#	not relavent or complete (framing) and we are still waiting (max wait == num_retries * timeout)
				#				
				num_rets -= 1
				if num_rets > 0
					@wait_condition.broadcast	# A nil response (we need the next data)
				else
					break;
				end
			end
			
			#
			# Ensure any status waits are started
			#
			if num_rets <= 0 && emit.present?
				@parent.end_emit_wait(emit)
				logger.debug "Emit cleared due to nil response: #{emit}"
			end
		end
		
		def attempt_retry(emit)
			@status_lock.lock		# for last_command
			if @pri_queue.empty? && @last_command[:retries] > 0	# no user defined replacements and retries left
				@last_command[:retries] -= 1
				@pri_queue.push(@last_command)
				@status_lock.unlock
				@dummy_queue.push(nil)	# informs our send loop that we are ready
			else
				@status_lock.unlock
				
				#
				# Ensure any status waits are started
				#
				if emit.present?
					@parent.end_emit_wait(emit)
					logger.debug "Emit cleared due to a failed command: #{emit}"
				end
			end
		end
	end

end