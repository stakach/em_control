require 'json'

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

	def load_page(page)
		command = {:control => "web", :command => page, :args => []}
		send(JSON.generate(command))
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
			command = {:control => "cam", :command => command.to_s, :args => []}
			send(JSON.generate(command), {:priority => 99})	# Cam control is low priority in case a camera is not plugged in
		end
	end
	
	def zoom(val)
		command = {:control => "cam", :command => "zoom", :args => [val.to_s]}
		send(JSON.generate(command))
	end


	#
	# Computer Response
	#
	def received(data)
		data = array_to_str(data)
		begin
			data = JSON.parse(data, {:symbolize_names => true})
			logger.debug "-- COMPUTER, sent: #{data.inspect}"
		rescue
			#
			# C# Code seems to be leaving a little bit of data for me to trip over
			#
			logger.debug "-- COMPUTER, bad data: #{data}"
			return true
		end
		
		if data[:command] == "authenticate"
			command = {:control => "auth", :command => setting(:domain), :args => [setting(:username), setting(:password)]}
			if @authenticated > 0
				one_shot(60) do		# Token retry (probably always fail - at least we can see in the logs)
					send(JSON.generate(command))
				end
				logger.info "-- Pod Computer, is refusing authentication"
			else
				send(JSON.generate(command))
			end
			@authenticated += 1
			logger.debug "-- COMPUTER, requested authentication"
		elsif data[:type] != nil
			self[data[:type].to_sym] = data[:data]	# zoom, tilt, pan
		else
			if !data[:result]
				logger.debug "-- COMPUTER, request failed for command: #{array_to_str(last_command)}"
				return false
			end
		end
		
		return true # Command success
	end
end