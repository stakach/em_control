module Control

	module Status
		include Observable


		def [] (status)
			status = status.to_sym if status.class == String
			@status_lock.synchronize {
				@status[status]
			}
		end
		
		def []= (status, data)
			status = status.to_sym if status.class == String
			old_data = nil
			@status_lock.synchronize {
				old_data = @status[status]
				@status[status] = data
				if @status_emit.has_key?(status)
					var = @status_emit.delete(status)
					
					begin
						var[1].cancel()
					rescue
					end
					
					var[0].broadcast
				end
			}
			if data != old_data
				changed								# so that the notify is applied
				logger.debug "#{self.class} status updated: #{status} = #{data}"
			end
			
			EM.defer do
				notify_observers(self, status, data)	# only notify changes
			end
		end
		
		attr_reader :status	# Should not be accessed like this for modification
	end

end