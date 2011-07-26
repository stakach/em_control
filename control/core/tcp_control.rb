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
			#			@logger.error "-- module #{@parent.class} error whilst calling: initiate_session --"
			#			@logger.error e.message
			#			@logger.error e.backtrace
			#		end
			#	end
			#end

	
			def connection_completed
				# set status
				resume if paused?
				@last_command[:wait] = false if !@last_command[:wait].nil?	# re-start event process
				@connect_retry = 0
				
				if !@tls_enabled
					call_connected
				else
					if !@parent.respond_to?(:certificates)
						start_tls
					else
						begin
							certs = @parent.certificates
							start_tls(certs)
						rescue => e
							EM.defer do
								@logger.error "-- module #{@parent.class} error whilst starting TLS with certificates --"
								@logger.error e.message
								@logger.error e.backtrace
							end
						end
					end
				end
			end
			
			def ssl_handshake_completed
				call_connected(get_peer_cert)		# this will mark the true connection complete stage for encrypted devices
			end
			

			def unbind
				# set offline
				@is_connected = false
				@buf = nil	# Any data in from TCP stream is now invalid
				
				EM.defer do
					@task_queue.push lambda {
						@parent[:connected] = false
						return unless @parent.respond_to?(:disconnected)
						begin
							@parent.disconnected
						rescue => e
							#
							# save from bad user code (don't want to deplete thread pool)
							#
							@logger.error "-- module #{@parent.class} error whilst calling: disconnected --"
							@logger.error e.message
							@logger.error e.backtrace
						end
					}
				end
				
				# attempt re-connect
				#	if !make and break
				settings = DeviceModule.lookup[@parent]
				
				if @connect_retry == 0
					begin
						reconnect Addrinfo.tcp(settings.ip, 80).ip_address, settings.port
						@connect_retry = 1
					rescue
						@connect_retry = 2
						EM.defer do
							@logger.info "-- module #{@parent.class} in em_control.rb, unbind --"
							@logger.info "Reconnect failed for #{settings.ip}:#{settings.port}"
						end
						do_reconnect(settings)
					end
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
	
					do_reconnect(settings)
				end
			end
			
			def do_reconnect(settings)
				EM.add_timer 5, proc { 
					begin
						reconnect Addrinfo.tcp(settings.ip, 80).ip_address, settings.port
					rescue
						do_reconnect(settings)
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