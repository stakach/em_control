#
# STD LIB
#
require 'observer'
require 'yaml'
require 'thread'
require 'monitor'
require 'Socket'	# for DNS lookups 
require 'Logger'


#
# Gems
#
require 'rubygems'
require 'eventmachine'
require 'em-priority-queue'
require 'em-http'
require 'rufus/scheduler'
require 'ipaddress'


#
# Library Files
#
require File.dirname(__FILE__) + '/control/resolver_pool.rb'
require File.dirname(__FILE__) + '/control/constants.rb'
require File.dirname(__FILE__) + '/control/utilities.rb'
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
require File.dirname(__FILE__) + '/control/interfaces/html5/html5.rb'


module Control
	
	ROOT_DIR = File.dirname(__FILE__)
	
	
	def self.scheduler
		@@scheduler
	end
	
	
	def self.resolver
		@@resolver
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
		@@resolver = ResolverPool.new
		
		EventMachine.run do
			#
			# Enable the scheduling system
			#
			@@scheduler = Rufus::Scheduler.start_new
			
			EM.defer do
				System.logger.debug "Started with #{EM.get_max_timers} timers avaliable"
				System.logger.debug "Started with #{EM.threadpool_size} threads in pool"
			end
			
			#
			# Start the UDP server
			# 	Disabled for now
			#
			#EM.open_datagram_socket "127.0.0.1", 0, DatagramServer

			#
			# Load the system based on the database
			#
			ControlSystem.all.each do |controller|
				EM.defer do
					begin
						System.logger.debug "Booting #{controller.name}"
						System.new_system(controller, @logLevel)
					rescue => e
						Control.print_error(Control::System.logger, e, {
							:message => "Error during boot",
							:level => Logger::FATAL
						})
						EventMachine::stop_event_loop
					end
				end
			end
			
			#
			# AutoLoad the interfaces (we should do this automatically)
			#
			#require ROOT_DIR + '/control/interfaces/telnet/telnet.rb'	Insecure
			#TelnetServer.start
			
			
			
			#
			# Emit connection counts for logging
			#
			@@scheduler.every '10s' do
				System.logger.info "There are #{EM.connection_count} connections to this server"
			end
			
			#
			# Start server
			#
			EM.add_timer(40) do
				System.start_websockets
			end
		end
	end
end

