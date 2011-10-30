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
				
				if !@tls_enabled.value
					@connected = true
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
								logger.error "-- module #{@parent.class} error whilst starting TLS with certificates --"
								logger.error e.message
								logger.error e.backtrace
							end
						end
					end
				end
			end
			
			def ssl_handshake_completed
				@connected = true
				EM.defer do
					call_connected(get_peer_cert)		# this will mark the true connection complete stage for encrypted devices
				end
			end
			

			def unbind
				# set offline
				@buf = nil	# Any data in from TCP stream is now invalid
				@connected = false
				@connect_retry = @connect_retry || Atomic.new(0)
				
				if @clear_queue_on_disconnect
					@dummy_queue = EM::Queue.new	# === dummy queue (informs when there is data to read from either the high or regular queues)
					@pri_queue = PriorityQueue.new	# high priority
					@send_queue = PriorityQueue.new	# regular priority
				end
				
				EM.defer do
					return if @shutting_down.value
					
					@parent.clear_emit_waits
					@task_queue.push lambda {
						@parent[:connected] = false
						return unless @parent.respond_to?(:disconnected)
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
					}
					
				
					# attempt re-connect
					#	if !make and break
					begin
						settings = DeviceModule.lookup(@parent)	#.reload # Don't reload here (user driven)
					rescue
						EM.defer do
							logger.fatal "-- module #{@parent.class} in tcp_control.rb, unbind --"
							logger.fatal "Failed to lookup settings. Device probably going offline."
							logger.error e.message
							logger.error e.backtrace
						end
						
						return	# Do not attempt to reconnect this device!
					end
					
					if @connect_retry.value == 0
						begin
							#
							# TODO:: https://github.com/eventmachine/eventmachine/blob/master/tests/test_resolver.rb
							# => Use the non-blocking resolver in the future
							#
							ip = Addrinfo.tcp(settings.ip, 80).ip_address
							EM.next_tick do
								reconnect ip, settings.port
							end
							@connect_retry.update { |v| v += 1}
						rescue
							@connect_retry.value = 2
							EM.defer do
								logger.info "-- module #{@parent.class} in tcp_control.rb, unbind --"
								logger.info "Reconnect failed for #{settings.ip}:#{settings.port}"
							end
							do_reconnect(settings)
						end
					else
						@connect_retry.update { |v| v += 1}
						#
						# log this once if had to retry more than once
						#
						if @connect_retry.value == 2
							EM.defer do
								logger.info "-- module #{@parent.class} in tcp_control.rb, unbind --"
								logger.info "Reconnect failed for #{settings.ip}:#{settings.port}"
							end
						end		
		
						do_reconnect(settings)
					end
				end
			end
			
			def do_reconnect(settings)
				EM.add_timer 5, proc {
					EM.defer do
						return if @shutting_down.value
						
						begin
							#
							# TODO:: https://github.com/eventmachine/eventmachine/blob/master/tests/test_resolver.rb
							# => Use the non-blocking resolver in the future
							#
							ip = Addrinfo.tcp(settings.ip, 80).ip_address
							EM.next_tick do
								reconnect ip, settings.port
							end
							#reconnect Addrinfo.tcp(settings.ip, 80).ip_address, settings.port
						rescue
							do_reconnect(settings)
						end
					end
				}
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