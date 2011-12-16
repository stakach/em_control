class CustomLifter < Control::Service
	
	def on_load
		base.default_request_options = {
			:keepalive => false,
			:retries => 4
		}
		base.config = {
			:inactivity_timeout => 0
		}
		
		@fail_count = 0
		
		self[:position_max] = 13200
		self[:position_min] = 0
	end
	
	def on_unload
		
	end
	
	
	#
	# Preset selection
	#
	def preset(number)
		request '/goto_preset', :query => {:preset => number}
	end
	
	
	def save_preset(number)
		request '/save_preset', :query => {:preset => number}
	end
	
	
	def up
		pos = self[:position] + 100
		if pos > self[:position_max]
			pos = self[:position_max]
		end
		goto(pos)
	end

	def down
		pos = self[:position] - 100
		if pos < 0
			pos = 0
		end
		goto(pos)
	end
	
	def goto(position)
		position = self[:position_max] if position > self[:position_max]
		request '/goto_pos', :query => {:pos => position}
	end

	def reset
		request '/reset'
	end
	
	
	def received(http, request)
		data = http.response
		
		logger.debug "Lifter sent: #{data}"
		
		if data =~ /ok!|fail!/i
			if data =~ /fail!/i
				@fail_count += 1
				if @fail_count >= 3
					self[:error] = data
				end
				return :failed
			else
				@fail_count = 0
				self[:error] = nil
				self[:position] = data.delete("^0-9").to_i
				return :success
			end
		else
			return :failed
		end
	end
end