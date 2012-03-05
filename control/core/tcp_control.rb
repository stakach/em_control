require 'atomic'

module Control

	class Device
	

		#
		# This is how sending works
		#		Send recieves data, turns a mutex on and sends the data
		#			-- It goes into the recieve mutex critical section and sleeps waiting for a response
		#			-- a timeout is used as a backup in case no response is received
		#		The recieve function does the following
		#			-- If the send lock is not active it processes the received data
		#			-- otherwise it notifies the send function that data is avaliable
		#
		class Base < EventMachine::Connection
			include Utilities
			include DeviceConnection
			
			#
			# EM Callbacks: --------------------------------------------------------
			#
			#def post_init
			#	return unless @parent.respond_to?(:initiate_session)
			#	
			#	begin
			#		@parent.initiate_session(@tls_enabled)
			#	rescue => e
			#		#
			#		# save from bad user code (don't want to deplete thread pool)
			#		#
			#		EM.defer do
			#			logger.error "-- module #{@parent.class} error whilst calling: initiate_session --"
			#			logger.error e.message
			#			logger.error e.backtrace
			#		end
			#	end
			#end

	
			def connection_completed
				# set status
				resume if paused?
				
				@connect_retry = @connect_retry || Atomic.new(0)
				EM.defer do
					@connect_retry.value = 0
				end
				
				if !@tls_enabled
					@connected = true
					@connecting = false
					EM.defer do
						call_connected
					end
				else
					if !@parent.respond_to?(:certificates)
						start_tls
					else
						begin
							certs = @parent.certificates
							start_tls(certs)
						rescue => e
							EM.defer do
								Control.print_error(logger, e, {
									:message => "module #{@parent.class} error whilst starting TLS with certificates",
									:level => Logger::ERROR
								})
							end
						end
					end
				end

				@make_occured = true
			end
			
			def ssl_handshake_completed
				@connected = true
				@connecting = false
				EM.defer do
					call_connected(get_peer_cert)		# this will mark the true connection complete stage for encrypted devices
				end
			end
			

			def unbind
				@connected = false	# set offline
				@connecting = false
				@disconnecting = false

				if @config[:flush_buffer_on_disconnect]
					process_response(@buf.flush, nil) unless @buf.nil?
				else
					@buf.flush unless @buf.nil?	# Any incomplete from TCP stream is now invalid
				end

				@connect_retry = @connect_retry || Atomic.new(0)
				
				if @config[:clear_queue_on_disconnect] || (@make_break && !@make_occured)
					@send_queue.clear
				end
				@make_occured = false
				
				EM.defer do
					if !@shutting_down.value
						
						@task_queue.push lambda {
							@parent[:connected] = false
							return unless @parent.respond_to?(:disconnected)
							begin
								@parent.disconnected
							rescue => e
								#
								# save from bad user code (don't want to deplete thread pool)
								#
								Control.print_error(logger, e, {
									:message => "module #{@parent.class} error whilst calling: disconnected",
									:level => Logger::ERROR
								})
							end
						}
					end
				end
				
				if !@make_break
					do_connect
				elsif @send_queue.size() > 0
					do_connect
				end
			end

			def do_connect
				if @disconnecting
					EM.next_tick do
						do_connect
					end
					return
				end
				return if @connected	# possible to get here

				makebreak = @make_break
				@connecting = true
				EM.defer do
					if !@shutting_down.value
						begin
							settings = DeviceModule.lookup(@parent)	#.reload # Don't reload here (user driven)
							
							@connect_retry.update { |v| v += 1}
							
							if @connect_retry.value == 1 || makebreak
								res = ResolverJob.new(settings.ip)
								res.callback {|ip|
									reconnect ip, settings.port
								}
								res.errback {|error|
									EM.defer do
										logger.info "module #{@parent.class} in tcp_control.rb, unbind"
										logger.info "Reconnect failed for #{settings.ip}:#{settings.port} - #{err.inspect}"
									end
									@connect_retry.value = 2
									do_reconnect(settings) unless makebreak
								}
							else
								#
								# log this once if had to retry more than once
								#
								if @connect_retry.value == 2
									logger.info "module #{@parent.class} in tcp_control.rb, unbind"
									logger.info "Reconnect failed for #{settings.ip}:#{settings.port}"
								else
									logger.debug "module #{@parent.class}:#{settings.ip}:#{settings.port} reconnect failed: #{@connect_retry.value}"
								end
				
								do_reconnect(settings)
							end
						rescue
							Control.print_error(logger, e, {
								:message => "module #{@parent.class} in tcp_control.rb, unbind\nFailed to lookup settings. Device probably going offline.",
								:level => Logger::FATAL
							})
							
							# Do not attempt to reconnect this device!
						end
					end
				end
			end
			
			def do_reconnect(settings)
				EM::Timer.new(5) do
					if !@shutting_down.value
						res = ResolverJob.new(settings.ip)
						res.callback {|ip|
							reconnect ip, settings.port
						}
						res.errback {|error|
							do_reconnect(settings)
						}
					end
				end
			end
			
			def receive_data(data)
				do_receive_data(data)
			end
			
			def do_send_data(data)
				send_data(data)
			end
		end
	end
end