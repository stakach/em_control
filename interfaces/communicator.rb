
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
		@connected_interfaces = []
		@command_lock = Mutex.new

		@status_register = {}
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
		if system.class == Fixnum
			
			return System.systems[System.systems.keys[system]].communicator.attach(interface)
		else
			system = system.to_sym if system.class == String
			return System.systems[system].communicator.attach(interface)
		end
	end




	#
	# Keep track of connected systems
	#
	def disconnected(interface)
		@connected_interfaces.delete(interface)
	end


	#
	# Keep track of status events
	#
	def register(interface, mod, status, &block)
		mod_sym = mod.class == String ? mod.to_sym : mod	# remember the symbol used by the interface to reference this module
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym]

		@status_register[mod] ||= {}
		@status_register[mod][status] ||= {}
		@status_register[mod][status][interface] = mod_sym
		
		mod.add_observer(self)
		
		#
		# Send the status to this requestor!
		#	This is the same as in update
		#
		if !mod[status].nil?
			begin
				function = "#{mod_sym}_#{status}_changed".to_sym
				if interface.respond_to?(function)
					interface.__send__(function, mod[status])
				else
					interface.notify(mod_sym, status, mod[status])
				end
			rescue => e
				p e.message
				p e.backtrace
			end
		end
	rescue
		begin
			block.call() if !block.nil?	# Block will inform of any errors
		rescue => e
			p e.message
			p e.backtrace
		end
	end

	def unregister(interface, mod, status, &block)
		mod_sym = mod.to_sym if mod.class == String
		status = status.to_sym if status.class == String
		
		mod = @system.modules[mod_sym]
		@status_register[mod] ||= {}
		@status_register[mod][status] ||= {}
		@status_register[mod][status].delete(interface)

		if @status_register[mod][status].empty?
			mod.delete_observer(self)
		end
	rescue
		begin
			block.call() if !block.nil?	# Block will inform of any errors
		rescue => e
			p e.message
			p e.backtrace
		end
	end

	def update(mod, status, data)
		p "COM: status update called"
		return if @status_register[mod].nil? || @status_register[mod][status].nil?
		
		#
		# Interfaces should implement the notify function
		#	Or a function for that particular event
		#
		@status_register[mod][status].each_pair do |interface, mod|
			begin
				function = "#{mod}_#{status}_changed".to_sym
				if interface.respond_to?(function)
					interface.__send__(function, data)
				else
					interface.notify(mod, status, data)
				end
			rescue => e
				p e.message
				p e.backtrace
			end
		end
	rescue => e
		p e.message
		p e.backtrace
	end
	
	#
	# Pass commands to the selected system
	#
	def send_command(mod, command, args = [], &block)
		#
		# Accept String, String (argument)
		#	String
		#
		mod = mod.to_sym if mod.class == String
		p "#{mod} #{command}"
		begin
			@command_lock.synchronize {
				@system.modules[mod].public_send(command, *args)	# Not send string however call function command
			}
		rescue
			begin
				block.call() if !block.nil?	# Block will inform of any errors
			rescue => e
				p e.message
				p e.backtrace
			end
		end
	end
	

	def attach(interface)
		@connected_interfaces << interface unless @connected_interfaces.include?(interface)
		return self
	end


	protected


	def unregister_all(interface)
		# TODO:: Important to stop memory leaks
	end
end
end