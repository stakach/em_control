

#
# This contains the basic constructs required for
#	serialised comms over TCP and UDP
#
module Control
	
	class Atomic
		def initialize(value)
			@value = value
			@value_lock = Mutex.new
		end
		
		def value
			@value_lock.synchronize { @value }
		end
		
		def value=(newval)
			@value_lock.synchronize { @value = newval }
		end
		
		def update
			@value_lock.synchronize {
				@value = yield @value
			}
		end
	end
	
	module DeviceConnection
		def initialize *args
			super
		
			@default_send_options = {
				:wait => true,			# Wait for response
				:delay => 0,			# Delay next send by x.y seconds
				:delay_on_recieve => 0,	# Delay next send after a recieve by x.y seconds (only works when we are waiting for responses)
				#:emit
				:max_waits => 3,
				:retries => 2,
				:hex_string => false,
				:timeout => 5,			# Timeout in seconds
				:priority => 0,
				:max_buffer => 1048576	# 1mb, probably overkill for a defualt
			}
			
			
			#
			# Queues
			#
			@task_queue = Queue.new			# basically we add tasks here that we want to run in a strict order (connect, disconnect)
			
			@receive_queue = EM::Queue.new	# So we can process responses in different ways
			
			@wait_queue = EM::Queue.new
			@dummy_queue = EM::Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
			@pri_queue = PriorityQueue.new	# high priority
			@send_queue = PriorityQueue.new	# regular priority
			
			
			#
			# Locks
			#
			@send_queue.extend(MonitorMixin)
			@recieved_lock = Mutex.new
			@task_lock = Mutex.new
			@status_lock = Mutex.new
			
			
			#
			# State
			#
			@connected = false
			@com_paused = false
			
			@command = nil
			@waiting = false
			@processing = false
			@last_sent_at = 0.0
			@last_recieve_at = 0.0
			@timeout = nil
			@max_buffer = @default_send_options[:max_buffer]	# 1mb, probably overkill for a defualt
			
			
			#
			# Configure links between objects (This is a very loose tie)
			#	Relies on serial loading of modules
			#
			@parent = Modules.loading[0]
			@parent.setbase(self)
			
			@tls_enabled = Atomic.new(@parent.secure_connection)
			@shutting_down = Atomic.new(false)
			
			
			#
			# Task event loop
			#
			EM.defer do
				while true
					begin
						task = @task_queue.pop
						break if @shutting_down.value
						
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
			# send loop
			#
			@wait_queue_proc = Proc.new do |ignore|
				return if ignore == :shutdown
				
				@dummy_queue.pop {|queue|
					return if queue == :shutdown
					
					if @pri_queue.empty?
						queue = @send_queue
					else
						queue = @pri_queue
					end
					
					begin
						command = queue.pop
						if command[:delay] > 0.0
							delay = @last_sent_at + delay - Time.now.to_f
							if delay > 0.0
								EM.add_timer delay_for do
									process_send(command)
								end
							else
								process_send(command)
							end
						else
							process_send(command)
						end
					rescue => e
						EM.defer do
							logger.error "module #{@parent.class} in device_connection.rb, base : error in send loop --"
							logger.error e.message
							logger.error e.backtrace
						end
					ensure
						ActiveRecord::Base.clear_active_connections!
						@wait_queue.pop &@wait_queue_proc
					end
				}
			end
			
			@wait_queue.push(nil)
			@wait_queue.pop &@wait_queue_proc
		end
		
		
		def process_send(command)	# this is on the reactor thread
			begin
				if !error?
					do_send_data(command[:data])
					
					@last_sent_at = Time.now.to_f
					@waiting = command[:wait]
					
					if @waiting
						@command = command
						@timeout = EM::Timer.new(command[:timeout]) {
							sending_timeout
						}
					else
						EM.next_tick do
							@wait_queue.push(nil)
						end			# keep it rolling!
					end
				else
					if @connected
						EM.next_tick do
							@wait_queue.push(nil)
						end				# Ignore sends on disconnected state
					else
						@com_paused = true
					end
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
				if @connected
					EM.next_tick do
						@wait_queue.push(nil)
					end				# Ignore sends on disconnected state
				else
					@com_paused = true
				end
			end
		end
		
		
		#
		# Data recieved
		#	Allow modules to set message delimiters for auto-buffering
		#	Default max buffer length == 1mb (setting can be overwritten)
		#	NOTE: The buffer cannot be defered otherwise there are concurrency issues 
		#
		def do_receive_data(data)
			@last_recieve_at = Time.now.to_f
			
			if @parent.respond_to?(:response_delimiter)
				begin
					del = @parent.response_delimiter
					if del.class == Array
						del = array_to_str(del)
					elsif del.class == Fixnum
						del = "" << del #array_to_str([del & 0xFF])
					end
					@buf ||= BufferedTokenizer.new(del, @max_buffer)    # Call back for character
					data = @buf.extract(data)
				rescue => e
					@buf = nil	# clear the buffer
					EM.defer do # Error in a thread
						logger.error "module #{@parent.class} error whilst setting delimiter --"
						logger.error e.message
						logger.error e.backtrace
					end
				end
			else
				data = [data]
			end
			
			if @waiting && data.length > 0
				if @processing
					@receive_queue.push(*data)
				else
					@processing = true
					process_response(data.shift, @command)
					if data.length > 0
						@receive_queue.push(*data)
					end
				end
			else
				data.each do |result|
					process_response(result, nil)
				end
			end
		end
		
		
		#
		# Caled from recieve
		#
		def process_response(response, command)
			EM.defer do
				do_process_response(response, command)
			end
		end
		
		def do_process_response(response, command)
			return if @shutting_down.value
			
			@recieved_lock.synchronize { 	# This lock protects the send queue lock when we are emiting status
				@send_queue.mon_synchronize {
					result = :abort
					begin
						if command.present?
							@parent.mark_emit_start(command[:emit]) if command[:emit].present?
						end
						if @parent.respond_to?(:received)
							result = @parent.received(response, command)
						else
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
					ensure
						if command.present?
							@parent.mark_emit_end(command[:emit]) if command[:emit].present?
						end
						ActiveRecord::Base.clear_active_connections!
					end
					
					if command.present? && command[:wait]
						EM.schedule do
							process_result(result)
						end
					end
				}
			}
		end
		
		
		def sending_timeout
			@timeout = true
			if !@processing
				@processing = true	# Ensure responses go into the queue
				
				process_result(:failed)
				
				EM.defer do
					logger.info "module #{@parent.class} timeout"
					logger.info "A response was not recieved for the current command"
				end
			end
		end
		
		
		def process_result(result)
			if @waiting
				if (result.nil? || result == :ignore) && @timeout != true && @command[:max_waits] > 0
					@command[:max_waits] -= 1
					
					@timeout.cancel
					@timeout = EM::Timer.new(@command[:timeout]) {
						sending_timeout
					}
					
					if @receive_queue.size() > 0
						@receive_queue.pop { |response|
							process_response(response, @command)
						}
					else
						@processing = false
					end
				else
					if @timeout != true
						@timeout.cancel
					end
					
					if (result == false || result == :failed) && @command[:retries] > 0 && @pri_queue.length == 0	# assume command failed, we need to retry
						@command[:retries] -= 1
						@pri_queue.push(@command)
						@dummy_queue.push(nil)
					end
					
					#else    result == :abort || result == :success || result == true || waits and retries exceeded
					
					@receive_queue.size().times do
						@receive_queue.pop { |response|
							process_response(response, nil)
						}
					end
					
					@processing = false
					@waiting = false
					
					if @command[:delay_on_recieve] > 0.0
						delay_for = (@last_recieve_at + @command[:delay_on_recieve] - Time.now.to_f)
						@command = nil 			# free memory
						
						if delay_for > 0.0
							EM.add_timer delay_for do
								@wait_queue.push(nil)
							end
						else
							@wait_queue.push(nil)
						end
					else
						@command = nil 			# free memory
						@wait_queue.push(nil)
					end
				end
			end
		end
		
		
		
		
		
		
		#
		# ----------------------------------------------------------------
		# Everything below here is called from a deferred thread
		#
		#
		def logger
			@parent.logger
		end
		
		def recieved_lock
			@send_queue		# for monitor use
		end
		
		
		#
		# Processes sends in strict order
		#
		def do_send_command(data, options = {})
			
			begin
				@status_lock.synchronize {
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
			queue = nil
			begin
				@send_queue.mon_exit
				@send_queue.mon_enter
				queue = @pri_queue		# Prioritise the command
			rescue
				queue = @send_queue
			end
			
			add_to_queue(options, queue)
				
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
		
		def add_to_queue(command, queue)
			EM.schedule do
				begin
					if @connected
						queue.push(command, command[:priority])
						@dummy_queue.push(nil)	# informs our send loop that we are ready
					end
				rescue
					EM.defer do
						logger.error "module #{@parent.class} in device_connection.rb, send : something went terribly wrong to get here --"
						logger.error e.message
						logger.error e.backtrace
					end
				end
			end
		end
		
		
		
		
		#
		# Connection state
		#
		def call_connected(*args)		# Called from a deferred thread
			#
			# NOTE:: Same as add parent in device module!!!
			#	TODO:: Should break into a module and include it
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
		
		
		
		def default_send_options= (options)
			@status_lock.synchronize {
				@default_send_options.merge!(options)
			}
			
			if options[:max_buffer].present?
				EM.schedule do
					@max_buffer = options[:max_buffer]
				end
			end
		end
		
		
		
		
		def shutdown(system)
			if @parent.leave_system(system) == 0
				@shutting_down.value = true
				
				close_connection
				
				@wait_queue.push(:shutdown)
				@dummy_queue.push(:shutdown)
				@send_queue.push(nil)
				
				@task_queue.push(nil)
				
				EM.defer do
					begin
						@parent[:connected] = false
						@parent.clear_emit_waits
						if @parent.respond_to?(:disconnected)
							@task_lock.synchronize {
								@parent.disconnected
							}
						end
					rescue => e
						#
						# save from bad user code (don't want to deplete thread pool)
						#
						logger.error "-- module #{@parent.class} error whilst calling: disconnected on shutdown --"
						logger.error e.message
						logger.error e.backtrace
					end
				end
			end
		end
		
	end
end