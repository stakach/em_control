

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
				:callback => nil,		# Alternative to the recieved function
				:retries => 2,
				:hex_string => false,
				:timeout => 5,			# Timeout in seconds
				:priority => 50,
				:retry_on_disconnect => true,
				:force_disconnect => false	# part of make and break options
			}
			
			
			#
			# Queues
			#
			@task_queue = Queue.new			# basically we add tasks here that we want to run in a strict order (connect, disconnect)
			
			@receive_queue = EM::Queue.new	# So we can process responses in different ways
			
			@wait_queue = EM::Queue.new
			@dummy_queue = EM::Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
			@pri_queue = EM::PriorityQueue.new(:fifo => true)	# high priority
			@send_queue = EM::PriorityQueue.new(:fifo => true)	# regular priority
			
			
			#
			# Locks
			#
			@recieved_lock = Mutex.new
			@task_lock = Mutex.new
			@status_lock = Mutex.new
			
			@send_monitor = Object.new.extend(MonitorMixin)
			
			
			#
			# State
			#
			@connected = false
			@connecting = false
			@disconnecting = false
			@com_paused = true
			
			@command = nil
			@waiting = false
			@processing = false
			@last_sent_at = 0.0
			@last_recieve_at = 0.0
			@timeout = nil
			
			@max_buffer = 1048576	# 1mb, probably overkill for a defualt
			@clear_queue_on_disconnect = false
			@flush_buffer_on_disconnect = false
			
			
			#
			# Configure links between objects (This is a very loose tie)
			#	Relies on serial loading of modules
			#
			@parent = Modules.loading[0]
			@parent.setbase(self)
			
			@tls_enabled = @parent.secure_connection
			if @parent.makebreak_connection
				@make_break = true
				@first_connect = true
			else
				@make_break = false
			end
			@make_occured = false
			
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
						Control.print_error(logger, e, {
							:message => "module #{@parent.class} in device_connection.rb, base : error in task loop",
							:level => Logger::ERROR
						})
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
			
			
			#
			# send loop
			#
			@wait_queue_proc = Proc.new do |ignore|
				if ignore != :shutdown
				
					@dummy_queue.pop {|queue|
						if queue != :shutdown
						
							if @pri_queue.empty?
								queue = @send_queue
							else
								queue = @pri_queue
							end
							
							queue.pop {|command| 
								begin
									if command[:delay] > 0.0
										delay = @last_sent_at + command[:delay] - Time.now.to_f
										if delay > 0.0
											EM.add_timer delay do
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
										Control.print_error(logger, e, {
											:message => "module #{@parent.class} in device_connection.rb, base : error in send loop",
											:level => Logger::ERROR
										})
									end
								ensure
									ActiveRecord::Base.clear_active_connections!
									@wait_queue.pop &@wait_queue_proc
								end
							}
						end
					}
				
				end
			end
			
			#@wait_queue.push(nil)		Start paused
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
						process_next_send(command)
					end
				else
					if @connected
						process_next_send(command)
					else
						if command[:retry_on_disconnect] || @make_break
							@pri_queue.push(command, command[:priority] - 99)	# TODO:: Need a better way to jump to front of queue
						end
						@com_paused = true
					end
				end
			rescue => e
				#
				# Save the thread in case of bad data in that send
				#
				EM.defer do
					Control.print_error(logger, e, {
						:message => "module #{@parent.class} in device_connection.rb, process_send : possible bad data",
						:level => Logger::ERROR
					})
				end
				if @connected
					process_next_send(command)
				else
					@com_paused = true
				end
			end
		end
		
		def process_next_send(command)
			if command[:force_disconnect]		# Allow connection control
				close_connection_after_writing
				@disconnecting = true
				@com_paused = true
			else
				EM.next_tick do
					@wait_queue.push(nil)	# Allows next response to process
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
					if @buf.nil?
						del = @parent.response_delimiter
						if del.class == Array
							del = array_to_str(del)
						elsif del.class == Fixnum
							del = "" << del #array_to_str([del & 0xFF])
						end
						@buf = BufferedTokenizer.new(del, @max_buffer)    # Call back for character
					end
					data = @buf.extract(data)
				rescue => e
					@buf = nil	# clear the buffer
					EM.defer do # Error in a thread
						Control.print_error(logger, e, {
							:message => "module #{@parent.class} error whilst setting delimiter",
							:level => Logger::ERROR
						})
					end
					data = [data]
				end
			else
				data = [data]
			end
			
			if @waiting && data.length > 0
				if @processing
					@receive_queue.push(*data)
				else
					@processing = true
					@timeout.cancel
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
				@send_monitor.mon_synchronize {
					result = :abort
					begin
						if @parent.respond_to?(:received)
							if command.present?
								@parent.mark_emit_start(command[:emit]) if command[:emit].present?
								if command[:callback].present?
									result = command[:callback].call(response, command)
									
									#
									# The data may still be usefull
									#
									if [nil, :ignore].include?(result)
										@parent.received(response, nil)
									end
								else
									result = @parent.received(response, command)
								end
							else
								#	logger.debug "Out of order response recieved for: #{@parent.class}"
								result = @parent.received(response, nil)
							end
						else
							if command.present? && command[:callback].present?
								result = command[:callback].call(response, command)
							else
								result = true
							end
						end
					rescue => e
						#
						# save from bad user code (don't want to deplete thread pool)
						#	This error should be logged in some consistent manner
						#
						Control.print_error(logger, e, {
							:message => "module #{@parent.class} error whilst calling: received",
							:level => Logger::ERROR
						})
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
			if !@processing && @connected	# Probably not needed...
				@processing = true	# Ensure responses go into the queue

				
				command = @command[:data] unless @command.nil?
				process_result(:failed)
				
				EM.defer do
					logger.info "module #{@parent.class} timeout"
					logger.info "A response was not recieved for the command: #{command}" unless command.nil?
				end
			end
		end
		
		
		def process_result(result)
			if @waiting
				if [nil, :ignore].include?(result) && @command[:max_waits] > 0
					@command[:max_waits] -= 1
					
					if @receive_queue.size() > 0
						@receive_queue.pop { |response|
							process_response(response, @command)
						}
					else
						@timeout = EM::Timer.new(@command[:timeout]) {
							sending_timeout
						}
						@processing = false
					end
				else					
					if [false, :failed].include?(result) && @command[:retries] > 0 && @pri_queue.length == 0	# assume command failed, we need to retry
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
						
						if delay_for > 0.0
							EM.add_timer delay_for do
								process_response_complete
							end
						else
							process_response_complete
						end
					else
						process_response_complete
					end
				end
			end
		end
		
		def process_response_complete
			if (@make_break && @dummy_queue.empty?) || @command[:force_disconnect]
				if @connected
					close_connection_after_writing
					@disconnecting = true
				end
				@com_paused = true
			else
				EM.next_tick do
					@wait_queue.push(nil)
				end
			end
			
			@command = nil 			# free memory
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
			@send_monitor		# for monitor use
		end
		
		
		#
		# Processes sends in strict order
		#
		def do_send_command(data, options = {}, *args, &block)
			
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
				
				if options[:callback].nil? && (args.length > 0 || block.present?)
					options[:callback] = args[0] unless args.empty? || args[0].class != Proc
					options[:callback] = block unless block.nil?
				end
			rescue => e
				Control.print_error(logger, e, {
					:message => "module #{@parent.class} in device_connection.rb, send : possible bad data or options hash",
					:level => Logger::ERROR
				})
				
				return true
			end
				
				
			#
			# Use a monitor here to allow for re-entrant locking
			#	This allows for a priority queue and we guarentee order of operations
			#
			queue = :send
			begin
				@send_monitor.mon_exit
				@send_monitor.mon_enter
				queue = :pri		# Prioritise the command
			rescue
			end
			
			EM.schedule do
				if queue == :send
					queue = @send_queue
				else
					queue = @pri_queue
				end
				add_to_queue(options, queue)
			end
				
			return false
		rescue => e
			#
			# Save from a fatal error
			#
			Control.print_error(logger, e, {
				:message => "module #{@parent.class} in device_connection.rb, send : something went terribly wrong to get here",
				:level => Logger::ERROR
			})
			return true
		end
		
		def add_to_queue(command, queue)
			begin
				if @connected || @make_break
					if @com_paused && !@make_break		# We are calling from connected function (and we are connected)
						command[:priority] -= 99	# To ensure this is the first to run.	TODO:: need a more solid way to achieve this
					elsif @make_break
						if !@connected && !@connecting
							EM.next_tick do
								do_connect
							end
						elsif @connected && @disconnecting
							EM.next_tick do
								add_to_queue(command, queue)
							end
							return	# Don't add to queue yet
						end
					end
					queue.push(command, command[:priority])
					@dummy_queue.push(nil)	# informs our send loop that we have a command loaded
				end
			rescue => e
				EM.defer do
					Control.print_error(logger, e, {
						:message => "module #{@parent.class} in device_connection.rb, send : something went terribly wrong to get here",
						:level => Logger::ERROR
					})
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
				
				begin
					@send_monitor.mon_synchronize { # Any sends in here are high priority (no emits as this function must return)
						@parent.connected(*args) if @parent.respond_to?(:connected)
					}
				rescue => e
					#
					# save from bad user code (don't want to deplete thread pool)
					#
					Control.print_error(logger, e, {
						:message => "module #{@parent.class} error whilst calling: connect",
						:level => Logger::ERROR
					})
				ensure
					EM.schedule do
						#
						# First connect if no commands pushed then we disconnect asap
						#
						if @make_break && @first_connect && @dummy_queue.size == 0
							close_connection_after_writing
							@disconnecting = true
							@com_paused = true
							@first_connect = false
						elsif @com_paused
							@com_paused = false
							@wait_queue.push(nil)
						end
					end
				end
			}
		end
		
		
		
		def default_send_options= (options)
			@status_lock.synchronize {
				@default_send_options.merge!(options)
			}
			
			if options[:max_buffer].present? || options[:clear_queue_on_disconnect].present? || options[:flush_buffer_on_disconnect].present?
				EM.schedule do
					@max_buffer = options[:max_buffer] unless options[:max_buffer].nil?
					@clear_queue_on_disconnect = options[:clear_queue_on_disconnect] unless options[:clear_queue_on_disconnect].nil?
					@flush_buffer_on_disconnect = options[:flush_buffer_on_disconnect] unless options[:flush_buffer_on_disconnect].nil?
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
						@parent[:connected] = false	# Communicator off at this point
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
						Control.print_error(logger, e, {
							:message => "module #{@parent.class} error whilst calling: disconnected on shutdown",
							:level => Logger::ERROR
						})
					ensure
						@parent.clear_active_timers
					end
				end
			end
		end
		
	end
end