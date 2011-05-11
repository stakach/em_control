require 'algorithms'

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
					:timeout => 5,
					:priority => 0
				}

				@receive_queue = Queue.new	# So we can process responses in different ways
				@dummy_queue = Queue.new	# === dummy queue
				@task_queue = Queue.new		# basically we add tasks here that we want to run in a strict order
				@send_queue = Containers::PriorityQueue.new
				@send_queue.extend(MonitorMixin)

				@queue_lock = Mutex.new		# Protects @send_queue modifications
				@receive_lock = Mutex.new	# Recieve data communications
				@send_lock = Mutex.new		# For in sync send and receives when required

				@wait_condition = ConditionVariable.new			# for waking and waiting on the revieve data
				@connected_condition = ConditionVariable.new		# for maintaining the current queue on disconnect and re-starting
		
				
				@status_lock = Mutex.new
				@last_command = {}
				@is_connected = false
				
				@connect_retry = 0		# delay if a retry happens straight again

				#
				# Configure links between objects (This is a very loose tie)
				#	Relies on serial loading of modules
				#
				@parent = Modules.loading
				@parent.setbase(self)
				@logger = @parent.logger
				@tls_enabled = DeviceModule.lookup[@parent][2]
				
				#
				# Task event loop
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
						end
					end
				end
				
				#
				# Send event loop
				#
				EM.defer do
					while true
						begin
							@dummy_queue.pop
							@queue_lock.synchronize {
								data = @send_queue.pop
							}
							@send_lock.synchronize {
								@send_queue.synchronize do
									process_send(data)
								end
							}
						rescue => e
							@logger.error "-- module #{@parent.class} in em_control.rb, base : error in send loop --"
							@logger.error e.message
							@logger.error e.backtrace
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
				#	This will allow for a priority queue and then we guarentee order of operations
				#
				if !options[:emit].nil?
					@parent.status_lock.lock
				end
				
				@queue_lock.synchronize {
					if @send_queue.mon_try_enter			# is this the same thread?
						@send_queue.push(options, 99)		# Prioritise the command
						@send_queue.mon_exit
					else
						@send_queue.push(options, options[:priority])
					end
				}
				@dummy_queue.push(nil)	# informs our send loop that we are ready for it
				
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
			

			#
			# EM Callbacks: --------------------------------------------------------
			#
			def post_init
				start_tls if @tls_enabled								# If we are using tls or ssl
				return unless @parent.respond_to?(:initiate_session)
				
				begin
					@parent.initiate_session(@tls_enabled)
				rescue => e
					#
					# save from bad user code (don't want to deplete thread pool)
					#
					@logger.error "-- module #{@parent.class} error whilst calling: initiate_session --"
					@logger.error e.message
					@logger.error e.backtrace
				end
			end
			

			def ssl_handshake_completed
				call_connected				# this will mark the true connection complete stage for encrypted devices
			end

	
			def connection_completed
				# set status
				
				resume if paused?
				@status_lock.synchronize {
					@last_command[:wait] = false if !@last_command[:wait].nil?	# re-start event process
				}
				@connect_retry = 0
				
				if !@tls_enabled
					call_connected
				end
			end
			

			def unbind
				@task_queue.push lambda {
					
					@status_lock.synchronize {
						# set offline
						@is_connected = false
					}
					
					#
					# Run on reactor thread to ensure immidiate execution
					#
					@parent[:connected] = false
					return unless @parent.respond_to?(:disconnected)

					begin
						@parent.disconnected
					rescue => e
						#
						# save from bad user code (don't want to deplete thread pool)
						#
						EM.defer do
							@logger.error "-- module #{@parent.class} error whilst calling: disconnected --"
							@logger.error e.message
							@logger.error e.backtrace
						end
					end
				}
				
				# attempt re-connect
				#	if !make and break
				settings = DeviceModule.lookup[@parent]
				
				if @connect_retry == 0
					reconnect settings.ip, settings.port
					@connect_retry = 1
				else
					@connect_retry += 1
					#
					# log this once if had to retry more than once
					#
					if @connect_retry == 2
						EM.defer do
							@logger.info "-- module #{@parent.class} in em_control.rb, unbind --"
							@logger.info "Reconnect failed for #{settings.ip}:#{settings.port}"
						end
					end		
	
					EM.add_timer 5, proc { 
						reconnect settings.ip, settings.port
					}
				end
			end

  
			def receive_data(data)
				EM.defer do
					@receive_queue.push(data)
					
					@receive_lock.lock
					if @send_lock.locked? && !@last_command[:emit].nil?	# There could be a bit of a race condition
						begin
							@timeout.cancel	# incase the timer is not active or nil
						rescue
						ensure
							@wait_condition.signal		# signal the thread to wakeup
							@receive_lock.unlock
						end
					else
						#
						# requires all the send locks ect to prevent recursive locks
						#	and avoid any errors (these would have been otherwise set during a send)
						#
						@receive_lock.unlock
						@send_lock.synchronize {
							self.process_data
						}
					end
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
				#
				@logger.error "-- module #{@parent.class} error whilst calling: received --"
				@logger.error e.message
				@logger.error e.backtrace
				
				return true
			end
	
	
			#
			# Ready state for next attempt
			#	WARN:: Must be called in send_lock critical section
			#
			#	A return false will always retry the command at the end of the queue
			#

			#
			# Send data
			#	send_lock is active
			#	send_queue monitor is active
			#
			def process_send(data)
				@status_lock.lock
				if @is_connected == false
					@status_lock.unlock
					@connected_condition.wait(@send_lock)
				end
				
				@status_lock.synchronize {
					@last_command = data
				}

				EM.schedule proc {	# Send data on the reactor thread
					begin
						if !error?
							send_data(data[:data])
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
				#	Synchronize the response
				#
				if data[:wait]
					process_response
				end
			end
			

			def process_response
				num_rets = nil
				@status_lock.synchronize {
					num_rets = @last_command[:max_waits]
				}
				begin
					wait_response
						
					if @receive_queue.empty?	# The wait timeout occured - retry command
						attempt_retry
						return
					else					# Process the data
						response = process_data
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
			

			def wait_response
				@receive_lock.synchronize {
					if @receive_queue.empty?
						@timeout = EM::Timer.new(@last_command[:timeout]) do 
							@receive_lock.synchronize {
								@wait_condition.signal		# wake up the thread
							}
							#
							# log the event here
							#
							EM.defer do
								@logger.debug "-- module #{@parent.class} in em_control.rb, wait_response --"
								@logger.debug "A response was not recieved for the current command"
							end
						end
						@wait_condition.wait(@receive_lock)
					end
				}
			end
			
			def attempt_retry
				@status_lock.synchronize {
					if !@send_queue.has_priority?(99) && @last_command[:retries] > 0	# no user defined replacements
						@last_command[:retries] -= 1
						@send_queue.push(@last_command, 99)
					end
				}
			end
			

			private
			

			def call_connected
				@task_queue.push lambda {
					@status_lock.synchronize {
						@is_connected = true
					}				

					@parent[:connected] = true
				
					@send_lock.synchronize {
						@connected_condition.signal		# wake up the thread
					}
					
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
		end
	end
end