#
#
# Manages displays in a digital signage network
# => number == number of displays
# => power_up and power_down are the cron job formatted times for start up and shutdown
# => displayX == the name of the display at that load order
#

class DisplayManagerLogic < Control::Logic

	def on_load
		update_settings
		schedule.every('1h') do
			update_settings
		end
	end
	
	
	def all_on
		for i in 1..self[:number]
			system["Display_#{i}"].power(On)
		end
	end
	
	
	def all_off
		for i in 1..self[:number]
			system["Display_#{i}"].power(Off)
		end
	end
	
	
	protected

	def update_settings
		self[:number] = setting(:number)
		
		for i in 1..self[:number]
			self["Display_#{i}"] = setting("display_#{i}")
		end
		
		if @power_up_time.nil? || @power_up_time != setting(:power_up)
			@power_up_time = setting(:power_up)
			
			@power_up.unschedule unless @power_up.nil?
			
			if @power_up_time != 'false'
				@power_up = schedule.every(@power_up_time) do
					logger.debug "-- Powering on the displays"
					all_on
				end
			end
		end
		
		if @power_down_time.nil? || @power_down_time != setting(:power_down)
			@power_down_time = setting(:power_down)
			
			@power_down.unschedule unless @power_down.nil?
			
			if @power_down_time != 'false'
				@power_down = schedule.every(@power_down_time) do
					logger.debug "-- Powering off the displays"
					all_off
				end
			end
		end
	end

end

