module Control

	module Status
		include Observable
		
		@status = {}
		@status_lock = Mutex.new

		def [] (status)
			@status_lock.synchronize {
				@status[status]
			}
		end
		
		def []= (status, data)
			@status_lock.synchronize {
				@status[status] = data
				notify_observers(self, status, data)
			}
		end
		
		attr_reader :status	# Should not be accessed like this for modification
	end

end