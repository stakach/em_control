module Control

	module Status
		include Observable
		
		@status = {}
		@status_lock = Mutex.new
		
		#
		# Lock only used in device.rb
		#
		@wait_condition = ConditionVariable.new
		@wait_status = nil

		def [] (status)
			@status_lock.synchronize {
				@status[status]
			}
		end
		
		def []= (status, data)
			@status_lock.synchronize {
				old_data = @status[status]
				@status[status] = data
				notify_observers(self, status, data) unless data == old_data	# only notify changes
				if status == @wait_status		# This is another reason to only have a single thread running commands at a time (also prevents interleaving)
					@wait_condition.signal		# wake up the thread
				end
			}
		end
		
		attr_reader :status	# Should not be accessed like this for modification
	end

end