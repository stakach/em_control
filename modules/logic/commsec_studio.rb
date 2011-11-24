# Settings avaliable
#-------------------
#
# morning_start
# afternoon_start
# night_start
#
class CommsecStudio < Control::Logic


	def do_preset(position, preset)
		system[:Audio].call_preset(8)
		system[:Audio].call_preset(preset)

		now = Time.now
		morning_start = Time.local(now.year, now.month, now.day, setting(:morning_start) || 6)
		afternoon_start = Time.local(now.year, now.month, now.day, setting(:afternoon_start) || 11)
		night_start = Time.local(now.year, now.month, now.day, setting(:night_start) || 17)

		if now < morning_start || now > night_start
			now = :night
		elsif now < afternoon_start
			now = :morning
		else
			now = :afternoon
		end

		if position == 1
			system[:Switcher].switch(:sdi_1_in => :pgm)
			case now
			when :morning
				system[:Lighting].start(1)
			when :afternoon
				system[:Lighting].start(2)
			when :night
				system[:Lighting].start(3)
			end
		else
			system[:Switcher].switch(:sdi_2_in => :pgm)

			if position == 2
				case now
				when :morning
					system[:Lighting].start(4)
				when :afternoon
					system[:Lighting].start(5)
				when :night
					system[:Lighting].start(6)
				end
			else
				system[:Lighting].start(7)
			end
		end
	end


	def shutdown
		system[:Audio].call_preset(7)
		system[:Switcher].switch(:black => :pgm)
		system[:Lighting].start(0)
	end

	def power_up
		system[:Audio].call_preset(8)
		system[:Switcher].switch(:colour_bar => :pgm)
	end


end


# position1 + position2
#-----------------------
## Morning		6 -> 12
## Afternoon		11 -> 17
## night		17 -> 6


# Position 3
#------------
## TV