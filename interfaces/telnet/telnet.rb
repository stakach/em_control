require 'rubygems'
require 'eventmachine'


require './ansi.rb'

module Control
class TelnetServer < EventMachine::Connection

	@@clients = {}
	
	def self.start
		EventMachine::start_server "127.0.0.1", 8080, TelnetServer
		puts 'running telnet server on 8080'
	end

	def initialize(*args)
		super
		
		@selected = nil
	end
		
	def post_init
		@identifier = self.object_id
		@@clients[@identifier] = self
		
		initiate_session
	end
 
	def receive_data(data)
		if data == "\b"
			if @input.length > 0
				send_data " \b"
				@input.chop!
			else
				send_data " "
			end
		elsif data =~ /.*\r\n$/
			@input = data.chop!.chop!
			if @input == "quit"
				disconnect
				return
			end
			begin
				if @selected.nil?
					num = @input.to_i
					if num == 0
						@selected = Communicator.select(self, @input)
					else
						@selected = Communicator.select(self, num)
					end
				else
					thecommand = @input.split(/\s*/, 3)
					@selected.send(thecommand[0], thecommand[1], thecommand[2].split(/\s*/))
				end
				send_line "  Command sent...", :green
			rescue
				send_line "  Invalid command...", :green
			end
			send_prompt("> ", :green)
			@input = ""
		else
			@input << data
		end
	end

	def unbind
		@@clients.delete(@identifier)
		@selected.disconnected(self)
	end
	
	protected
	
	def initiate_session
		@input = ""
		send_line("Please select from the following systems:", :green)
		send_line("-----------------------------------------", :green)
		system = Communicator.system_list
		system.each_index { |x| send_line(" #{x}) #{system[x]}", :green) }
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
