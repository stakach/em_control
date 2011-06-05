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
			def post_init
				start_tls if @tls_enabled								# If we are using tls or ssl
				return unless @parent.respond_to?(:initiate_session)
				
				begin
					@parent.initiate_session(@tls_enabled)
				rescue => e
					#
					# save from bad user code (don't want to deplete thread pool)
					#
					EM.defer do
						@logger.error "-- module #{@parent.class} error whilst calling: initiate_session --"
						@logger.error e.message
						@logger.error e.backtrace
					end
				end
			end
			

			def ssl_handshake_completed
				call_connected(get_peer_cert)		# this will mark the true connection complete stage for encrypted devices
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
				@status_lock.synchronize {
						# set offline
					@is_connected = false
				}			

				@task_queue.push lambda {
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
					do_receive_data(data)
				end
			end
			
			def do_send_data(data)
				send_data(data)
			end
		end
	end
end