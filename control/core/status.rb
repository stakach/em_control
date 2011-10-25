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
				old_data = @status[status]
				@status[status] = data
				if @status_emit.has_key?(status) && @status_emit[status].length > 0
					@status_emit[status].shift.broadcast
					logger.debug "Emit clear success: #{status}"
				end
			}
			if data != old_data
				changed								# so that the notify is applied
				logger.debug "#{self.class} status updated: #{status} = #{data}"
			end
			
			
			notify_observers(self, status, data)	# only notify changes
		end
		
		attr_reader :status	# Should not be accessed like this for modification
	end

end