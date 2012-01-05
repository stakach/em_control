module Control

	module Status
		include Observable


		def [] (status)
			status = status.to_sym if status.class == String
			@status_lock.synchronize {
				return @status[status]
			}
		end
		
		def []= (status, data)
			status = status.to_sym if status.class == String
			old_data = nil
			@status_lock.synchronize {
				old_data = check_for_emit(status, data)
			}
			if data != old_data
				changed								# so that the notify is applied
				logger.debug "#{self.class} status updated: #{status} = #{data}"
			end
			
			
			notify_observers(self, status, data)	# only notify changes
		end
		
		attr_reader :status	# Should not be accessed like this for modification
		
		
		def mark_emit_start(status)
			@status_lock.synchronize {
				if @status_emit.has_key?(status) && @status_emit[status].length > 0
					@emit_has_occured = false
				end
			}
		end
		
		def mark_emit_end(status)
			@status_lock.synchronize {
				if @status_emit.has_key?(status) && @status_emit[status].length > 0
					if not @emit_has_occured
						@emit_has_occured = true
						@status_emit[status].shift.broadcast
						logger.debug "A forced emit on #{status} occured"
					end
				end
			}
		end
		
		
		def clear_emit_waits
			@status_lock.synchronize {
				@status_emit.each_value do |status|
					while status.length > 0
						status.shift.broadcast
					end
				end
			}
		end
		
		
		protected
		
		def check_for_emit(status, data)
		
			old_data = @status[status]
			@status[status] = data
			if @status_emit.has_key?(status) && @status_emit[status].length > 0
				begin
					@base.received_lock.mon_exit				# check we are in the send queue
					@base.received_lock.mon_enter
					@status_emit[status].shift.broadcast	# wake up the thread
					@emit_has_occured = true
				rescue
					# Emit can only occur in the recieve queue
					# We must already have the lock
					logger.debug "An emit on #{status} occured outside received function"
				end
				#logger.debug "Emit clear success: #{status}"
			end
			old_data
			
		end
	end

end