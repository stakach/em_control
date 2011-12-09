require 'uri'

#
# This contains the basic constructs required for
#	serialised comms over TCP and UDP
# => TODO:: SSL
#
module Control	
	class HttpService
		VERBS = [:get, :post, :put, :delete, :head]
		
		def initialize(parent, settings)
			
			@config = {
				:priority_bonus => 20,
				
				
				:connect_timeout => 5,
				:inactivity_timeout => 10
				# :ssl
				# :bind
				# :proxy
			}
			@uri = URI.parse(settings.ip)
			@uri.port = settings.port
			@connection = EventMachine::HttpRequest.new(@uri, @config)
		
			@default_request_options = {
				:wait => true,			# Wait for response
				:delay => 0,			# Delay next request by x.y seconds
				:delay_on_recieve => 0,	# Delay next request after a recieve by x.y seconds (only works when we are waiting for responses)
				#:emit
				:retries => 2,
				:priority => 50,
				
				#
				# EM:http related
				#
				# query
				# body
				:path => '/',
				#
				:timeout => 10,			# inactivity_timeout in seconds
				:connect_timeout => 5,
				:keepalive => true,
				:redirects => 0,
				:verb => :get,
				:stream => false,		# send chunked data
				
				:callback => nil,		# Alternative to the recieved function
				:errback => nil,
			}
			
			
			#
			# Queues
			#
			@task_queue = Queue.new			# basically we add tasks here that we want to run in a strict order
			@wait_queue = EM::Queue.new
			@send_queue = PriorityQueue.new	# regular priority
			
			
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
			@last_sent_at = 0.0
			@last_recieve_at = 0.0
			
			
			#
			# Configure links between objects
			#
			@parent = parent
			@parent.setbase(self)
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
							:message => "module #{@parent.class} in http_service.rb : error in task loop",
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
							
					@send_queue.pop {|command|
						if command != :shutdown
							
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
							
						end
					}
				end
			end
			
			@wait_queue.push(nil)	# Don't start paused
			@wait_queue.pop &@wait_queue_proc
		end
		
		
		def process_send(command)	# this is on the reactor thread
			begin
				http = @connection.__send__(command[:verb], command)
				
				@last_sent_at = Time.now.to_f
				
				http.callback do
					process_response(http, command)
				end
				
				if command[:wait]
					http.errback do
						command = command[:data]
						process_result(:failed, command)
						
						EM.defer do
							logger.info "module #{@parent.class} error: #{http.error}"
							logger.info "A response was not recieved for the command: #{command[:path]}"
						end
					end
				else
					process_next_send
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
				
				process_next_send
			end
		end
		
		def process_next_send
			EM.next_tick do
				@wait_queue.push(nil)	# Allows next response to process
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
						@parent.mark_emit_start(command[:emit]) if command[:emit].present?
						
						if @parent.respond_to?(:received)
							if command[:callback].present?
								result = command[:callback].call(response, command)
							else
								result = @parent.received(response, command)
							end
						else
							if command[:callback].present?
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
						@parent.mark_emit_end(command[:emit]) if command[:emit].present?
						ActiveRecord::Base.clear_active_connections!
					end
					
					if command[:wait]
						EM.schedule do
							process_result(result, command)
						end
					end
				}
			}
		end
		
		
		def process_result(result, command)
			if [false, :failed].include?(result) && command[:retries] > 0	# assume command failed, we need to retry
				command[:retries] -= 1
				@send_queue.push(command, command[:priority] - @config[:priority_bonus])
			end
			
			#else    result == :abort || result == :success || result == true || waits and retries exceeded
			
			if command[:delay_on_recieve] > 0.0
				delay_for = (@last_recieve_at + command[:delay_on_recieve] - Time.now.to_f)
				
				if delay_for > 0.0
					EM.add_timer delay_for do
						process_next_send
					end
				else
					process_next_send
				end
			else
				process_next_send
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
			@send_monitor		# for monitor use
		end
		
		
		#
		# Processes sends in strict order
		#
		def do_send_command(path, options = {}, *args, &block)
			
			begin
				@status_lock.synchronize {
					options = @default_send_options.merge(options)
				}
				options[:path] = path unless path.nil?
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
			bonus = false
			begin
				@send_monitor.mon_exit
				@send_monitor.mon_enter
				bonus = true
			rescue
			end
			
			EM.schedule do
				if bonus
					options[:priority] -= @config[:priority_bonus]
				end
				@send_queue.push(options, options[:priority])
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
		
		
		
		def default_send_options= (options)
			@status_lock.synchronize {
				@default_send_options.merge!(options)
			}
		end
		
		def config= (options)
			EM.schedule do
				@config.merge!(options)
				@connection = EventMachine::HttpRequest.new(@uri, @config)
			end
		end
		
		
		
		def shutdown(system)
			if @parent.leave_system(system) == 0
				@shutting_down.value = true
				@wait_queue.push(:shutdown)
				@send_queue.push(:shutdown)
				@task_queue.push(nil)
				
				EM.defer do
					begin
						@parent.clear_emit_waits
						if @parent.respond_to?(:on_unload)
							@task_lock.synchronize {
								@parent.on_unload
							}
						end
					rescue => e
						#
						# save from bad user code (don't want to deplete thread pool)
						#
						Control.print_error(logger, e, {
							:message => "module #{@parent.class} error whilst calling: on_unload on shutdown",
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