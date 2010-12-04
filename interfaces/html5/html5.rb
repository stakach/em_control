
require 'em-websocket'


EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8080) do |socket|

	@clients = {}
		
	socket.onopen {
		@clients << socket
	}
 
	socket.onmessage { |data|
		#
		# Attach socket here to system
		#	then process commands
		#
		
		socket.send "Echo: #{data}"
	}

	socket.onclose {
		@clients.remove(socket)
	}

end

