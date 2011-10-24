
module Control
	class Device
		include Status	# The observable pattern (Should not be called directly)
		include Constants
		include Utilities
		
		def initialize(tls)
			@systems = []

			#
			# Status variables
			#	NOTE:: if changed then change in logic.rb 
			#
			@secure_connection = tls
			@status = {}
			@status_lock = Mutex.new
			@system_lock = Mutex.new
			@status_emit = {}	# status => condition_variable
		end

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

	
		def last_command	# get the last command sent that was (this is very contextual)
			@base.last_command
		end
		
		def command_option(key)
			@base.command_option(key)
		end
		

		def logger
			@system_lock.synchronize {
				return @systems[0].logger unless @systems.empty?
			}
			System.logger
		end
		

		#
		# required by base for send logic
		#
		attr_reader :status_lock
		attr_reader :secure_connection
		attr_reader :systems
		attr_reader :base
		

		protected
		
		
		#
		# Configuration and settings
		#
		def config
			DeviceModule.lookup(self)
		end
		
		def setting(name)
			val = config.settings.where("name = ?", name).first || config.dependency.settings.where("name = ?", name).first
			
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

		def send(data, options = {})
			error = @base.send(data, options)
			
			if !options[:emit].nil?
				return @status[options[:emit]] if error == true
				
				#
				# The command is queued - we need to wait for the status to be emited
				#
				if @status_emit[options[:emit]].nil?
					@status_emit[options[:emit]] = [ConditionVariable.new]
				end
				
				timeout = options[:emit_wait] || (@base.default_send_options[:retries] * @base.default_send_options[:timeout])
				@status_emit[options[:emit]] << one_shot(timeout) do
					@status_lock.synchronize {
						if @status_emit.has_key?(options[:emit])
							var = @status_emit.delete(options[:emit])
							var[0].broadcast		# wake up the thread
								
							#
							# log the event here
							#
							EM.defer do
								logger.debug "-- module #{self.class} in device.rb, send --"
								logger.debug "An emit timeout occured"
							end
						end
					}
				end

				@status_emit[options[:emit]][0].wait(@status_lock)
				
				#
				# Locked in send if emit is set
				#
				@status_lock.unlock
					
				return @status[options[:emit]]
			end
		end
	end
end
