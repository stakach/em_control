module Control
	class System

		@@systems = {}	# system_name => system instance
		@@schemes = {}	# scheme_id => system instance
		@@logger = nil

		def initialize(scheme, log_level)
			super		

			if @@schemes[scheme.id].nil?

				@modules = {}	# scheme modules	:name => module instance (device or logic)
				@communicator = Control::Communicator.new(self)
				@log_level = log_level
		
				@logger = Log4r::Logger.new("#{scheme.name}")
				file = Log4r::RollingFileOutputter.new(scheme.name, {:maxsize => 4194304, :filename => "#{ROOT_DIR}/interface/log/#{scheme.name}.log"})	# 4mb file
				file.level = log_level
				@logger.add(Log4r::Outputter['console'], Log4r::Outputter['udp'], file)	# common console output for all venues

				#
				# Setup the systems links
				#
				@@systems[scheme.name.to_sym] = self
				@@schemes[scheme.id] = self
		
				#
				# Load the modules ()
				#	
				#Dependency.for_scheme(scheme).each do |dep|
				#	if @@modules[dep.id].nil?
				#		Scheme.reload_module(dep)		# This is the re-load code function (live bug fixing - removing functions does not work)
				#	end
				#end
			
				scheme.devices.includes(:dependency).each do |device|
					load_hooks(device, DeviceModule.new(device))
				end
			
				scheme.logics.includes(:dependency).each do |logic|
					load_hooks(logic, LogicModule.new(logic))
				end
			else
				#
				# TODO:: Check for changes and update the system instance
				#	Update system name on existing instance and the name references to that instance
				#	clear existing hooks
				#	update hooks
				#	Change log level if required
				#
				#	TODO:: requires a lock around hooks (so can't read and update at the same time)
				#
			end
		end
	
		
		#
		# System Logger
		#	
		def self.logger
			@@logger
		end
		
		def self.logger=(log)
			@@logger = log
		end
		
		def self.schemes
			@@schemes
		end
	
		def self.systems
			@@systems
		end
		
		def self.[] (system)
			system = system.to_sym if system.class == String
			@@systems[system]
		end
	
		#
		#	Module accessor
		#
		def [] (mod)
			mod = mod.to_sym if mod.class == String
			@modules[mod].instance
		end

		attr_reader :modules
		attr_reader :communicator
		attr_accessor :logger
	

		protected
	
	
		def load_hooks(device, mod)
			module_name = device.dependency.module_name
			count = 2
				
			if not @modules[module_name.to_sym].nil?
				while @modules["#{module_name}_#{count}".to_sym].nil?
					count += 1
				end
				module_name = "#{module_name}_#{count}"
			else
				@modules["#{module_name}_1".to_sym] = mod
			end
			@modules[module_name.to_sym] = mod
		end
	end
end