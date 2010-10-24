require 'rubygems'
require 'eventmachine'


class Device < EventMachine::Connection
	# self.connected if self.respond_to?(:connected)

	@online = false
	@offline = true


	def post_init
		# set online
		self.connected if self.respond_to?(:connected)
	end

  
	def receive_data(data)
		EM.defer()
	end


	def unbind
		# set offline
		self.disconnected if self.respond_to?(:disconnected)
	end
end


class Projector < Device
	
end


class NECProj < Projector
	def connected
		
	end


	def recieved(data)
		
	end


	def disconnected
		
	end
end



EventMachine.run do
	EM.connect 'microsoft.com', 80, NECProj
	EM.connect 'google.com', 80, NECProj
end

