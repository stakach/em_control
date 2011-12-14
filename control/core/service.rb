module Control

	class Service
		include ModuleCore
		
		def initialize
			@systems = []

			#
			# Status variables
			#	NOTE:: if changed then change in logic.rb 
			#
			@status = {}
			@status_lock = Mutex.new
			@system_lock = Mutex.new
			@status_emit = {}	# status => condition_variable
			@status_waiting = false
		end
		
		protected
		
		def request(path, options = {}, *args, &block)
			
			if options[:emit].present?
				logger.debug "Emit set: #{options[:emit]}"
				@status_lock.lock
			end
			
			error = @base.do_send_request(data, options, *args, &block)
			
			if options[:emit].present?
				begin
					emit = options[:emit]
					stat = @status[emit]
					return stat if error == true
					
					#
					# The command is queued - we need to wait for the status to be emited
					#
					if @status_emit[emit].nil?
						@status_emit[emit] = [ConditionVariable.new]
					else
						@status_emit[emit].push(ConditionVariable.new)
					end
					
					#
					# Allow commands following the current one to execute as high priority if in recieve
					#	Ensures all commands that should be high priority are
					#
					begin
						@base.recieved_lock.mon_exit
						@status_emit[emit].last.wait(@status_lock)	# wait for the emit to occur
						@base.recieved_lock.mon_enter
					rescue
						@status_emit[emit].last.wait(@status_lock)	# wait for the emit to occur
					end
					
					stat = @status[emit]
					return stat
				ensure
					@status_lock.unlock
				end
			end
			
		end
	end
	
end