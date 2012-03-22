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
			old_data = check_for_emit(status, data)
			
			if data != old_data
				changed								# so that the notify is applied
				logger.debug "#{self.class} status updated: #{status} = #{data}"
			end
			
			
			notify_observers(self, status, data)	# only notify changes
		end
		
		attr_reader :status	# Should not be accessed like this for modification
		
		
		def mark_emit_start(status)
			@status_lock.synchronize {
				@emit_hasnt_occured = status
			}
		end
		
		def mark_emit_end
			@status_lock.synchronize {
				@emit_hasnt_occured.each_pair do | key, block |
					data = @status[key]
					task do
						begin
							block.call(data)
						ensure
							ActiveRecord::Base.clear_active_connections!
						end
					end
					logger.debug "A forced emit on #{status} occured"
				end
				
				@emit_hasnt_occured = nil
			}
		end
		
		
		protected
		
		
		def check_for_emit(status, data)
			@status_lock.synchronize {
				old_data = @status[status]
				@status[status] = data
				
				if @emit_hasnt_occured.present?
					begin
						if @emit_hasnt_occured.has_key?(status)
							@base.received_lock.mon_exit				# check we are in the recieved queue
							@base.received_lock.mon_enter
						
							block = @emit_hasnt_occured.delete(status)
							task do
								begin
									block.call(data)
								ensure
									ActiveRecord::Base.clear_active_connections!
								end
							end
						#logger.debug "Emit clear success: #{status}"
						end
					rescue
						logger.debug "An emit on #{status} occured outside received function"
					end
				end
				
				return old_data
			}
		end
	end

end