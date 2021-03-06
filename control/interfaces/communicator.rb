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
		
		@shutdown = true
	end
	

	def logger
		@system.logger
	end
	
	
	def shutdown
		@status_lock.synchronize {
			@shutdown = true
			@system.modules.each_value do |mod|
				mod.instance.delete_observer(self)
			end
			@status_register = {}			
			@connected_interfaces.each_key do |soc|
				soc.shutdown
			end
		}
		logger.debug "-- Communicator shutdown"
	end
	
	def start(nolog = false)			# Logging isn't active for the very first of these
		@status_lock.synchronize {
			@shutdown = false
		}
		logger.debug "-- Communicator started" unless nolog
	end

	
	#
	# Systems avaliable to this user
	#
	def self.system_list(user)
		response = {:ids => [], :names => []}
		
		if user.class == User
			user.control_systems.select('control_systems.id, control_systems.name').each do |controller|
				if !!System[controller.name.to_sym]
					response[:ids] << controller.id
					response[:names] << controller.name
				end
			end 	# We ignore token requests here as they should know the system they can connect to
		end
		return response
	end
	
	#
	# Set the system to communicate with
	#	Up to interfaces to maintain stability here (They should deal with errors)
	#
	def self.select(user, interface, system)
		System.logger.debug "-- Interface #{interface.class} attempting to select system #{system}"
		if system == 0
			return nil unless user[:system_admin]
			System.communicator.attach(interface)
		else
			sys = nil
			
			if user.class == User
				sys = user.control_systems.select('control_systems.name').where('control_systems.id = ? AND control_systems.active = ?', system.to_i, true).first
				
			elsif user.class == TrustedDevice && user.control_system_id == system.to_i
				sys = User.find(user.user_id).control_systems.select('control_systems.name, control_systems.active').where('control_systems.id = ?', system.to_i).first
				if sys.nil?
					#
					# Kill comms, this key is not valid
					#	Invalidate key
					#
					user.expires = Time.now
					user.save
					interface.shutdown
					return nil
				elsif sys.active == false
					#
					# System offline... Disconnect
					#
					return false
				end
			end
			
			system = sys.nil? ? nil : sys.name.to_sym
			if System[system].nil?
				interface.shutdown	#kill comms
				return nil
			end
			
			System.logger.debug "-- Interface #{interface.class} selected system #{system}"
			return System[system].communicator.attach(interface)
		end
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
		logger.debug "-- Interface #{interface.class} disconnected" unless logger.nil?
	end


	#
	# Keep track of status events
	#
	def register(interface, mod, status, &block)
		mod_sym = mod.class == String ? mod.to_sym : mod	# remember the symbol used by the interface to reference this module
		status = status.to_sym if status.class == String
		
		if @system.modules[mod_sym].present?
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
					Control.print_error(logger, e, {
						:message => "in communicator.rb, register : bad interface or user module code",
						:level => Logger::ERROR
					})
				end
			end
		else
			logger.warn "in communicator.rb, register : #{interface.class} called register on a bad module name"
			block.call() unless block.nil?	# Block will inform of any errors
		end
	rescue => e
		begin
			Control.print_error(logger, e, {
				:message => "in communicator.rb, register : #{interface.class} failed to register #{mod.inspect}.#{status.inspect}",
				:level => Logger::ERROR
			})
			block.call() unless block.nil?	# Block will inform of any errors
		rescue => x
			Control.print_error(logger, x, {
				:message => "in communicator.rb, register : #{interface.class} provided a bad block",
				:level => Logger::WARN
			})
		end
	ensure
		ActiveRecord::Base.clear_active_connections!
	end

	def unregister(interface, mod, status, &block)
		mod_sym = mod.to_sym if mod.class == String
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym].instance
		logger.debug "Interface #{interface.class} unregistered #{mod_sym}:#{status}"

		@status_lock.synchronize {
			@status_register[mod] ||= {}
			@status_register[mod][status] ||= {}
			@status_register[mod][status].delete(interface)
			@connected_interfaces[interface].delete(@status_register[mod][status]) unless @connected_interfaces[interface].nil?

			#
			# TODO:: deleteing the observer will delete all status updates
			#	This needs to be more selective.
			#	We only delete the observer if all the mod[status]'s are empty
			#
			#if @status_register[mod][status].empty?
			#	mod.delete_observer(self)
			#end
		}
	rescue => e
		logger.warn "in communicator.rb, unregister : #{interface.class} called unregister when it was not needed"
		#logger.warn e.message
		#logger.warn e.backtrace
		begin
			block.call() if !block.nil?	# Block will inform of any errors
		rescue => x
			Control.print_error(logger, x, {
				:message => "in communicator.rb, unregister : #{interface.class} provided a bad block",
				:level => Logger::WARN
			})
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
						Control.print_error(logger, e, {
							:message => "in communicator.rb, update : bad interface or user module code",
							:level => Logger::ERROR
						})
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				end
			end
		}
	rescue => e
		Control.print_error(logger, e, {
			:message => "in communicator.rb, update : This should never happen",
			:level => Logger::ERROR
		})
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
			Control.print_error(logger, e, {
				:message => "module #{mod} in communicator.rb, send_command : command unavaliable or bad module code",
				:level => Logger::WARN
			})
			begin
				block.call() unless block.nil?	# Block will inform of any errors
			rescue => x
				Control.print_error(logger, x, {
					:message => "in communicator.rb, send_command : interface provided bad block",
					:level => Logger::ERROR
				})
			end
		ensure
			ActiveRecord::Base.clear_active_connections!
		end
	end
	
	
	def attach(interface)
		@status_lock.synchronize {
			return nil if @shutdown || interface.nil?
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