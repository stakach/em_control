require 'rubygems'
require 'eventmachine'


require './ansi.rb'

class TelnetServer < EventMachine::Connection

	@@clients = {}

	def initialize(*args)
		super
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
			if @input == ""
				@input = data.chop!.chop!
			end
			if @input == "quit"
				disconnect
				return
			end
			send_line "  Command processed...", :green
			send_prompt("> ", :green)
			@input = ""
		else
			@input << data
		end
	end

	def unbind
		@@clients.delete(@identifier)
	end
	
	protected
	
	def initiate_session
		@input = ""
		send_line("Please select from the following systems:", :green)
		send_line("-----------------------------------------", :green)
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

EventMachine::run {
	EventMachine::start_server "127.0.0.1", 8080, TelnetServer
	puts 'running echo server on 8080'
}
