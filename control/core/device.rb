
module Control
	module ModuleCore
		include Status	# The observable pattern (Should not be called directly)
		include Constants
		include Utilities
		
		#
		# Sets up a link for the user code to the eventmachine class
		#	This way the namespace is clean.
		#
		def setbase(base)
			@base = base
		end
		
		
		def join_system(system)
			@system_lock.synchronize {
				@systems << system
			}
		end
		
		def leave_system(system)
			@system_lock.synchronize {
				@systems.delete(system)
				return @systems.length
			}
		end
		
		def clear_active_timers
			return if @active_timers.nil?
			
			@active_timers.synchronize {
				while @active_timers.length > 0
					@active_timers[0].cancel
				end
			}
		end
		
		
		#def command_successful(result)			# TODO:: needs a re-think
		#	@base.process_data_result(result)
		#end
		

		def logger
			@system_lock.synchronize {
				return @systems[0].logger unless @systems.empty?
			}
			System.logger
		end
		
		attr_reader :systems
		attr_reader :base
		
		
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
		
		
		#
		# Configuration and settings
		#		
		def setting(name)
			val = config.settings.where("name = ?", name.to_s).first || config.dependency.settings.where("name = ?", name.to_s).first
			
			if !val.nil?
				case val.value_type
					when 0
						return val.text_value
					when 1
						return val.integer_value
					when 2
						return val.float_value
					when 3
						return val.datetime_value
				end
			end
			
			return nil
		end
	end
	
	class Device
		include ModuleCore
		
		def initialize(tls, makebreak)
			@systems = []

			#
			# Status variables
			#	NOTE:: if changed then change in logic.rb 
			#
			@secure_connection = tls
			@makebreak_connection = makebreak
			@status = {}
			@status_lock = Mutex.new
			@system_lock = Mutex.new
			@status_emit = {}	# status => condition_variable
			@status_waiting = false
		end

		
		

		#
		# required by base for send logic
		#
		attr_reader :secure_connection
		attr_reader :makebreak_connection
		

		protected
		
		
		def config
			DeviceModule.lookup(self)
		end
		

		def send(data, options = {}, *args, &block)
			if options[:emit].present?
				logger.debug "Emit set: #{options[:emit]}"
				@status_lock.lock
			end
			
			error = @base.do_send_command(data, options, *args, &block)
			
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
