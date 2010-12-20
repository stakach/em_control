module Control

	module Status
		include Observable
		
		

		def [] (status)
			@status_lock.synchronize {
				@status[status]
			}
		end
		
		def []= (status, data)
			old_data = nil
			@status_lock.synchronize {
				old_data = @status[status]
				@status[status] = data
				if @status_emit.has_key?(status)
					var = @status_emit.delete(status)
					var.broadcast
				end
			}
			changed unless data == old_data
			notify_observers(self, status, data)	# only notify changes
		end
		
		attr_reader :status	# Should not be accessed like this for modification
	end

end