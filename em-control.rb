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
require 'log4r'
require "log4r/formatter/log4jxmlformatter"
require "log4r/outputter/udpoutputter"



#
# Library Files
#
require File.dirname(__FILE__) + '/control/constants.rb'
require File.dirname(__FILE__) + '/control/utilities.rb'
require File.dirname(__FILE__) + '/control/priority_queue.rb'
require File.dirname(__FILE__) + '/control/core/modules.rb'
require File.dirname(__FILE__) + '/control/core/status.rb'
require File.dirname(__FILE__) + '/control/core/device.rb'
require File.dirname(__FILE__) + '/control/core/logic.rb'
require File.dirname(__FILE__) + '/control/interfaces/communicator.rb'
require File.dirname(__FILE__) + '/control/interfaces/deferred.rb'
require File.dirname(__FILE__) + '/control/core/system.rb'
require File.dirname(__FILE__) + '/control/core/device_connection.rb'
require File.dirname(__FILE__) + '/control/core/datagram_server.rb'
require File.dirname(__FILE__) + '/control/core/tcp_control.rb'



module Control

	DEBUG = 1
	INFO = 2
	WARN = 3
	ERROR = 4
	FATAL = 5
	
	ROOT_DIR = File.dirname(__FILE__)
	
	#
	# Load the config file and start the modules
	#
	def self.set_log_level(level)
		if level.nil?
			@logLevel = INFO
		else
			@logLevel = case level.downcase.to_sym
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
		file = Log4r::RollingFileOutputter.new("system", {:maxsize => 4194304, :filename => "#{ROOT_DIR}/interface/log/system.log"})	# 4mb file
		file.level = @logLevel
			
		System.logger.add(Log4r::Outputter['console'], Log4r::Outputter['udp'], file)
	end
	
	def self.start
		EventMachine.run do
			#
			# Start the UDP server
			#
			EM.open_datagram_socket "127.0.0.1", 0, DatagramServer

			#
			# Load the system based on the database
			#
			Controller.all.each do |controller|
				System.new(controller, @logLevel)
			end
			
			#
			# AutoLoad the interfaces (we should do this automatically)
			#
			require ROOT_DIR + '/control/interfaces/telnet/telnet.rb'
			TelnetServer.start
			require ROOT_DIR + '/control/interfaces/html5/html5.rb'
		end
	end
end

