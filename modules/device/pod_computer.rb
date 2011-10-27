#
# Settings required:
#	* domain (domain that we will be authenticating against)
#	* username (username for authentication)
#	* password (password for authentication)
#
# (built in)
# connected
#
class PodComputer < Control::Device

	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def on_load
		#
		# Setup constants
		#
		@authenticated = 0
	end
	
	def connected(cert)	# if we want to check the TLS cert
		
	end
	
	def disconnected
		@authenticated = 0
	end
	
	def launch_application(app)
		do_send({:control => "app", :command => app, :args => []})
	end
	


	#
	# Camera controls
	#
	CAM_OPERATIONS = [:up, :down, :left, :right, :center, :zoomin, :zoomout]
	
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	CAM_OPERATIONS.each do |command|
		define_method command do |*args|
			# Cam control is low priority in case a camera is not plugged in
			do_send({:control => "cam", :command => command.to_s, :args => []}, {:priority => 99})
		end
	end
	
	def zoom(val)
		do_send({:control => "cam", :command => "zoom", :args => [val.to_s]})
	end


	
	def response_delimiter
		0x03	# Used to interpret the end of a message
	end
	
	def received(data, command)
		#
		# Remove the start character and grab the message
		#
		data = data.split("" << 0x02)
		if data.length >= 2
			data = data[-1]	# valid response
		else
			return true	# Invalid data (we shall ignore)
		end
		
		#
		# Convert the message into a naitive object
		#
		data = JSON.parse(data, {:symbolize_names => true})
		
		#
		# Process the response
		#
		if data[:command] == "authenticate"
			command = {:control => "auth", :command => setting(:domain), :args => [setting(:username), setting(:password)]}
			if @authenticated > 0
				#
				# Token retry (probably always fail - at least we can see in the logs)
				#	We don't want to flood the network with useless commands
				#
				one_shot(60) do
					do_send(command)
				end
				logger.info "-- Pod Computer, is refusing authentication"
			else
				do_send(command)
			end
			@authenticated += 1
			logger.debug "-- Pod Computer, requested authentication"
		elsif data[:type] != nil
			self["#{data[:device]}_#{data[:type]}"] = data	# zoom, tilt, pan
			return nil	# This is out of order data
		else
			if !data[:result]
				logger.debug "-- Pod Computer, request failed for command: #{array_to_str(last_command)}"
				return false
			end
		end
		
		return true # Command success
	end
	
	private
	
	def do_send(command, options = {})
		send("" << 0x02 << JSON.generate(command) << 0x03, options)
	end
end