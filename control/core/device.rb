
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
			begin
=begin
				if options[:emit].present?
					logger.debug "Emit set: #{options[:emit]}"
					@status_lock.lock
					emit = options[:emit]
					#emit = options.delete(:emit)
				end
=end
				emit = options.delete(:emit)	# TODO:: Emit can't block deferred thread
				error = @base.do_send_command(data, options, *args, &block)
			
				if emit.present?
					return @status[emit]
					
=begin
					stat = @status[emit]
					return stat if error == true  # TODO:: fix deadlock
					
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
						#
						# Check for emit in received
						#	TODO:: ensure early response sent else log the issue and return current value
						#
						@base.received_lock.mon_exit
						@status_emit[emit].last.wait(@status_lock)	# wait for the emit to occur
						@base.received_lock.mon_enter
					rescue
						@status_emit[emit].last.wait(@status_lock)	# wait for the emit to occur
					end
					
					stat = @status[emit]
					return stat
=end
				end
			rescue => e
				Control.print_error(logger, e, {
					:message => "module #{self.class} in send",
					:level => Logger::ERROR
				})
			ensure
				begin
					@status_lock.unlock if @status_lock.locked?
				rescue
				end
			end
		end
	end
end
