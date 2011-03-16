#
# STD LIB
#
require 'observer'
require 'yaml'
require 'thread'
require 'monitor'



#
# Gems
#
require 'rubygems'
require 'eventmachine'
require 'active_support'
require 'active_support/core_ext/string'
require 'log4r'
require "log4r/formatter/log4jxmlformatter"
require "log4r/outputter/udpoutputter"



#
# Library Files
#
require './constants.rb'
require './utilities.rb'
require './modules.rb'
require './status.rb'
require './device.rb'
require './logic.rb'
require './interfaces/communicator.rb'
require './interfaces/deferred.rb'
require './system.rb'
require './control_base.rb'


module Control

	DEBUG = 1
	INFO = 2
	WARN = 3
	ERROR = 4
	FATAL = 5
	
	#
	# Load the config file and start the modules
	#
	def self.set_log_level
		if ARGV[0].nil?
			@logLevel = INFO
		else
			@logLevel = case ARGV[0].downcase.to_sym
				when :debug
					DEBUG
				when :warn
					WARN
				when :error
					ERROR
				else
					INFO
			end
		end
		
		#
		# Console output
		#
		console = Log4r::StdoutOutputter.new 'console'
		console.level = @logLevel
		
		#
		# Chainsaw output (live UDP debugging)
		#
		log4jformat = Log4r::Log4jXmlFormatter.new
		udpout = Log4r::UDPOutputter.new 'udp', {:hostname => "localhost", :port => 8071}
		udpout.formatter = log4jformat
		
		#
		# System level logger
		#
		System.logger = Log4r::Logger.new("system")
		file = Log4r::RollingFileOutputter.new("system", {:maxsize => 4194304, :filename => "system.txt"})	# 4mb file
		file.level = @logLevel
			
		System.logger.add(Log4r::Outputter['console'], Log4r::Outputter['udp'], file)
	end
	
	def self.start
		EventMachine.run do
			require 'yaml'
			settings = YAML.load_file 'settings.yml'
			settings.each do |name, room|
				system = System.new(name.to_sym, @logLevel)
				room.each do |settings, mod_name|
					case settings.to_sym
						when :devices
							mod_name.each do |key, value|
								require "./devices/#{key}.rb"
								device = key.classify.constantize.new(system)
								system.modules << device
								ip = nil
								port = nil
								tls = false
								tcp = true
								System.logger.info "Loaded device module #{key} : #{value}"
								value.each do |field, data|
									case field.to_sym
										when :names
											symdata = []
											data.each {|item|
												item = item.to_sym
												system.modules[item] = device
												symdata << item
											}
											system.modules[device] = symdata
										when :ip
											ip = data
										when :port
											port = data.to_i
										when :tls
											tls = data
										when :udp
											tcp = !data
									end
								end
								Modules.connections[device] = [ip, port, tls]
								if tcp
									EM.connect ip, port, Device::Base
								else
									#
									# Check if a UDP server has been created
									#	Create a UDP server using open_datagram_socket (datagram_server.rb)
									# Register the instansiated device with the server
									#	undef send
									#	def alternative for send (which sends datagram on base)
									#	set connected status (we will always be connected as this is a state-less protocol)
									#	call connected
									#
								end
							end
						when :controllers
							mod_name.each do |key, value|
								require "./controllers/#{key}.rb"
								control = key.classify.constantize.new(system)
								system.modules << control
								System.logger.info "Loaded control module #{key} : #{value}"
								value.each do |field, data|
									case field.to_sym
										when :names
											symdata = []
											data.each {|item|
												item = item.to_sym
												system.modules[item] = control
												symdata << item
											}
											system.modules[control] = symdata
									end
								end
							end
					end
				end
			end

			#devices = Devices.new
			#devices << NECProj.new
			#devices[:projector1] = Devices.last
			#Devices.connections[Devices.last] = ["127.0.0.1", 8081]
			#EM.connect "127.0.0.1", 8081, Device::Base
			

			#
			# AutoLoad the interfaces
			#
			require './interfaces/telnet/telnet.rb'
			TelnetServer.start
			require './interfaces/html5/html5.rb'
		end
	end
end



#
# Will be controlled in our launch program
#
Control.set_log_level
Control.start
