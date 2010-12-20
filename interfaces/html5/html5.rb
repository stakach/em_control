
require 'em-websocket'


#
# TODO::Need to define a command structure and build a JS library for sending commands easily from the interface
#		USE JSON!!!
#			https://gist.github.com/299789
#			http://blog.new-bamboo.co.uk/2010/2/10/json-event-based-convention-websockets
#


class HTML5Monitor
	@@clients = []

	def self.register(id)
		@@clients << id
	end
	
	def self.unregister(id)
		@@clients.delete(id)
	end
	
	def self.count
		@@clients.length
	end
end


EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 81) do |socket|
	
	
	socket.onopen {
		#
		# Setup status variable here :)
		#	We could use a 
		#
		HTML5Monitor.register(self)
		p 'HTML5 Browser connected'
		socket.send "select system"
	}
	
	socket.onmessage { |data|
		#
		# Attach socket here to system
		#	then process commands
		#
		begin
			socket.send "Echo: #{data}"
		rescue
			p "HTML5 socket send failed"
		end
	}

	socket.onclose {
		HTML5Monitor.unregister(self)
		p "There are now #{HTML5Monitor.count} HTML5 clients connected"
	}

end

puts 'running HTML5 socket server on 81'
