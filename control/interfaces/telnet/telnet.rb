#require 'rubygems'
#require 'eventmachine'


require "#{File.dirname(__FILE__)}/ansi.rb"
require 'json'

module Control
	class TelnetServer < Deferred
	
		def initialize(*args)
			super
			
			@input_lock = Mutex.new
		end

		def self.start
			EventMachine::start_server "127.0.0.1", 23, TelnetServer
			System.logger.info 'running telnet server on 23'
		end
 
		def received
			@input_lock.synchronize {
				data = @receive_queue.pop(true)		
				if data == "\b"
					if @input.length > 0
						send_data " \b"
						@input.chop!
					else
						send_data " "
					end
				elsif data =~ /.*\r\n$/
		
					#
					# TODO:: For linux we need to chop! twice here
					#	Windows @input is already complete
					#

					if @input =~ /^(quit|exit)$/i 
						disconnect
						return
					end

					if @input != "" && !@input.nil?
						if @selected.nil?
							if @input =~ /^\d+$/
								@selected = Communicator.select(self, @input.to_i)
							else
								@selected = Communicator.select(self, @input)
							end
							send_line " system #{@input} selected...", :green
						else
							thecommand = @input.split(/\s|\./, 3)
							@input = ""
							on_fail = lambda {
								send_line(" invalid command", :green)
								send_prompt("> ", :green)
								send_prompt(@input)
							}
							if thecommand[0] =~ /register/i
								@selected.register(self, thecommand[1], thecommand[2], &on_fail)
							elsif thecommand[0] =~ /unregister/i
								@selected.unregister(self, thecommand[1], thecommand[2], &on_fail)
							elsif thecommand[2].nil?
								@selected.send_command(thecommand[0], thecommand[1], &on_fail)
							elsif ['{','['].include?(thecommand[2][0])
								@selected.send_command(thecommand[0], thecommand[1], JSON.parse(thecommand[2], {:symbolize_names => true}), &on_fail)
							else
								@selected.send_command(thecommand[0], thecommand[1], thecommand[2], &on_fail)
							end
							send_line " sent...", :green
						end
					end

					send_prompt("> ", :green)
					@input = ""
				else #if data =~ /^[a-zA-Z0-9\., _-]*$/
					@input << data
				end
			}
		end
		
		def notify(mod_sym, stat_sym, data)
			send_line("\r\nStatus: #{mod_sym}:#{stat_sym}==#{data}", :green)
			send_prompt("> ", :green)
			@input_lock.synchronize {
				send(@input) if !@input.empty?
			}
		end
	
		protected
	
		def initiate_session
			@input_lock.synchronize {
				@input = ""
			}
			send_line("Please select from the following systems:", :green)
			send_line("-----------------------------------------", :green)
			system = Communicator.system_list
			system.each_index { |x| send_line(" #{x}: #{system[x]}", :green) }
			send_prompt("> ", :green)
		end
	
		def disconnect
			send_line("Goodbye.", :green)
			close_connection_after_writing
		end
	
		def send_line(data, color=nil)
			send(data, color, true)
		end

		def send_prompt(data, color=nil)
			send(data, color, false)
		end
	
		def send(data, color=nil, newline=false)
			if newline
				data = data + "\r\n" 
			end
 
			case color
			when :red
				send_data(ANSI.red(data))
			when :green
				send_data(ANSI.green(data))
			else
				send_data(data)
			end
		end
	end
end

#EventMachine::run {
#	EventMachine::start_server "127.0.0.1", 8080, TelnetServer
#	puts 'running echo server on 8080'
#}
