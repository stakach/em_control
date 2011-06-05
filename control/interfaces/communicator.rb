
#
# There should be one communicator per system that handles the interface interfaces
#	This will pass on registered status requirements and call functions as requested
#
#	Interfaces will have to have a base class that abstracts the event machine code so that
#	nothing runs on the reactor thread.
#
module Control
class Communicator

	def initialize(system)
		@system = system
		
		@command_lock = Mutex.new
		@status_lock = Mutex.new
		
		@status_register = {}
		@connected_interfaces = {}
	end
	

	def logger
		@system.logger
	end

	
	#
	# Systems avaliable to this communicator
	#
	def self.system_list
		System.systems.keys
	end
	
	#
	# Set the system to communicate with
	#	Up to interfaces to maintain stability here (They should deal with errors)
	#
	def self.select(interface, system)
		System.logger.debug "-- Interface #{interface.class} selected system #{system}"
		system = system.to_sym if system.class == String
		return nil if System.systems[system].nil?
		return System.systems[system].communicator.attach(interface)
	end




	#
	# Keep track of connected systems
	#
	def disconnected(interface)
		@status_lock.synchronize {
			status_array = @connected_interfaces.delete(interface)
			status_array.each do |status_hash|
				status_hash.delete(interface)
			end
			#
			# TODO::Refactor required
			#	This still isn't perfect as we could be observing modules we are not using...
			#
		}
		logger.debug "-- Interface #{interface.class} disconnected"	
	end


	#
	# Keep track of status events
	#
	def register(interface, mod, status, &block)
		mod_sym = mod.class == String ? mod.to_sym : mod	# remember the symbol used by the interface to reference this module
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym].instance	# most efficient

		theVal = nil
		@status_lock.synchronize {
			@status_register[mod] ||= {}
			@status_register[mod][status] ||= {}
			@status_register[mod][status][interface] = mod_sym
			@connected_interfaces[interface] << @status_register[mod][status] unless @connected_interfaces[interface].nil?
			theVal = mod[status]
		}
		
		mod.add_observer(self)
		logger.debug "-- Interface #{interface.class} registered #{mod_sym}:#{status}"
		
		#
		# Send the status to this requestor!
		#	This is the same as in update
		#
		if !theVal.nil?
			begin
				function = "#{mod_sym.to_s.downcase}_#{status}_changed".to_sym
				
				if interface.respond_to?(function)
					interface.__send__(function, theVal)
				else
					interface.notify(mod_sym, status, theVal)
				end
			rescue => e
				logger.error "-- in communicator.rb, register : bad interface or user module code --"
				logger.error e.message
				logger.error e.backtrace
			end
		end
	rescue => e
		logger.warn "-- in communicator.rb, register : #{interface.class} called register on a bad module name --"
		logger.debug e.message
		logger.debug e.backtrace
		begin
			block.call() unless block.nil?	# Block will inform of any errors
		rescue => x
			logger.warn "-- in communicator.rb, register : #{interface.class} provided a bad block --"
			logger.warn x.message
			logger.warn x.backtrace
		end
	ensure
		ActiveRecord::Base.clear_active_connections!
	end

	def unregister(interface, mod, status, &block)
		mod_sym = mod.to_sym if mod.class == String
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym].instance
		logger.debug "-- Interface #{interface.class} unregistered #{mod_sym}:#{status}"

		@status_lock.synchronize {
			@status_register[mod] ||= {}
			@status_register[mod][status] ||= {}
			@status_register[mod][status].delete(interface)
			@connected_interfaces[interface].delete(@status_register[mod][status]) unless @connected_interfaces[interface].nil?

			if @status_register[mod][status].empty?
				mod.delete_observer(self)
			end
		}
	rescue => e
		logger.warn "-- in communicator.rb, unregister : #{interface.class} called unregister when it was not needed --"
		#logger.warn e.message
		#logger.warn e.backtrace
		begin
			block.call() if !block.nil?	# Block will inform of any errors
		rescue => x
			logger.warn "-- in communicator.rb, unregister : #{interface.class} provided a bad block --"
			logger.warn x.message
			logger.warn x.backtrace
		end
	end

	def update(mod, status, data)
		@status_lock.synchronize {
			return if @status_register[mod].nil? || @status_register[mod][status].nil?
		
			#
			# Interfaces should implement the notify function
			#	Or a function for that particular event
			#
			@status_register[mod][status].each_pair do |interface, mod|
				EM.defer do	# to avoid deadlock
					begin
						function = "#{mod.to_s.downcase}_#{status}_changed".to_sym
						if interface.respond_to?(function)				# Can provide a function to deal with status updates
							interface.__send__(function, data)
						else
							interface.notify(mod, status, data)
						end
					rescue => e
						logger.error "-- in communicator.rb, update : bad interface or user module code --"
						logger.error e.message
						logger.error e.backtrace
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
		}
	rescue => e
		logger.error "-- in communicator.rb, update : I hope no one ever sees this --"
		logger.error e.message
		logger.error e.backtrace
	end
	
	#
	# Pass commands to the selected system
	#
	def send_command(mod, command, *args, &block)
		#
		# Accept String, argument array
		#	String
		#
		mod = mod.to_sym if mod.class == String
		logger.debug "-- Command requested #{mod}.#{command}(#{args})"
		
		begin
			@command_lock.synchronize {
				@system.modules[mod].instance.public_send(command, *args)	# Not send string however call function command
			}
		rescue => e
			logger.warn "-- module #{mod} in communicator.rb, send_command : command unavaliable or bad module code --"
			logger.warn e.message
			logger.warn e.backtrace
			begin
				block.call() unless block.nil?	# Block will inform of any errors
			rescue => x
				logger.error "-- in communicator.rb, send_command : interface provided bad block --"
				logger.error x.message
				logger.error x.backtrace
			end
		ensure
			ActiveRecord::Base.clear_active_connections!
		end
	end
	

	def attach(interface)
		@status_lock.synchronize {
			@connected_interfaces[interface] = [] unless @connected_interfaces.include?(interface)
		}
		return self
	end


	protected


	def unregister_all(interface)
		# TODO:: Important to stop memory leaks
	end
end
end