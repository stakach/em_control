#
# STD LIB
#
require 'observer'
require 'yaml'
require 'thread'
require 'monitor'
require 'Socket'	# for DNS lookups (EM isn't every good at this)
require 'Logger'


#
# Gems
#
require 'rubygems'
require 'eventmachine'
require 'em-priority-queue'
require 'em-http'
#require 'em-resolv-replace'
require 'rufus/scheduler'


#
# Library Files
#
require File.dirname(__FILE__) + '/control/constants.rb'
require File.dirname(__FILE__) + '/control/utilities.rb'
require File.dirname(__FILE__) + '/control/priority_queue.rb'
require File.dirname(__FILE__) + '/control/core/modules.rb'
require File.dirname(__FILE__) + '/control/core/status.rb'
require File.dirname(__FILE__) + '/control/core/device.rb'
require File.dirname(__FILE__) + '/control/core/service.rb'
require File.dirname(__FILE__) + '/control/core/logic.rb'
require File.dirname(__FILE__) + '/control/interfaces/communicator.rb'
require File.dirname(__FILE__) + '/control/interfaces/deferred.rb'
require File.dirname(__FILE__) + '/control/core/system.rb'
require File.dirname(__FILE__) + '/control/core/device_connection.rb'
require File.dirname(__FILE__) + '/control/core/datagram_server.rb'
require File.dirname(__FILE__) + '/control/core/tcp_control.rb'
require File.dirname(__FILE__) + '/control/core/http_service.rb'


module Control
	
	ROOT_DIR = File.dirname(__FILE__)
	
	
	def self.scheduler
		@@scheduler
	end
	
	
	def self.get_log_level(level)
		if level.nil?
			return Logger::INFO
		else
			return case level.downcase.to_sym
				when :debug
					Logger::DEBUG
				when :warn
					Logger::WARN
				when :error
					Logger::ERROR
				else
					Logger::INFO
			end
		end
	end
	
	#
	# Load the config file and start the modules
	#
	def self.set_log_level(level)
		@logLevel = get_log_level(level)
		
		#
		# System level logger
		#
		if Rails.env.production?
			System.logger = Logger.new("#{ROOT_DIR}/interface/log/system.log", 10, 4194304)
		else
			System.logger = Logger.new(STDOUT)
		end
		System.logger.formatter = proc { |severity, datetime, progname, msg|
			"#{datetime.strftime("%d/%m/%Y @ %I:%M%p")} #{severity}: #{System} - #{msg}\n"
		}
	end
	
	def self.start
		EventMachine.run do
			#
			# Enable the scheduling system
			#
			@@scheduler = Rufus::Scheduler.start_new
			
			
			#
			# Start the UDP server
			#
			EM.open_datagram_socket "127.0.0.1", 0, DatagramServer

			#
			# Load the system based on the database
			#
			ControlSystem.all.each do |controller|
				EM.defer do
					begin
						System.logger.debug "Booting #{controller.name}"
						System.new(controller, @logLevel)
					rescue => e
						System.logger.error "error during boot"
						System.logger.error e.message
						System.logger.error e.backtrace
					end
				end
			end
			
			#
			# AutoLoad the interfaces (we should do this automatically)
			#
			#require ROOT_DIR + '/control/interfaces/telnet/telnet.rb'	Insecure
			#TelnetServer.start
			require ROOT_DIR + '/control/interfaces/html5/html5.rb'
		end
	end
end

