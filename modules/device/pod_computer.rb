require 'json'

class PodComputer < Control::Device

	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def onLoad
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
	# Computer Response
	#
	def received(data)
		data = array_to_str(data)
		begin
			data = JSON.parse(data, {:symbolize_names => true})
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
			logger.debug "-- COMPUTER, requested authentication: #{command.inspect}"
		else
			if !data[:result]
				logger.debug "-- COMPUTER, request failed for command: #{array_to_str(last_command)}"
				return false
			end
		end
		
		return true # Command success
	end
end