
module Control
	class System

		@@systems = {}
		
		def self.systems
			@@systems
		end
		
		def self.[] (system)
			@@systems[system]
		end

		def initialize(name, log_level)
			@name = name
			@modules = Modules.new
			@communicator = Communicator.new(self)
			
			@logger = Log4r::Logger.new("#{@name.to_s}")
			file = Log4r::RollingFileOutputter.new(@name.to_s, {:maxsize => 4194304, :filename => "#{@name.to_s}.txt"})	# 4mb file
			file.level = log_level
			
			@logger.add(Log4r::Outputter['console'], Log4r::Outputter['udp'], file)	# common console output for all venues
			
			#
			# TODO:: Add a logger output that can output to a connected system or SNMP
			#

			@@systems[name] = self
		end
		
		def [] (mod)
			@modules[mod]
		end

		attr_reader :modules
		attr_reader :name
		attr_reader :communicator
		attr_accessor :logger
	
	end
end
