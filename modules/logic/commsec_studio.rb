# Settings avaliable
#-------------------
#
# morning_start
# afternoon_start
# night_start
#
class CommsecStudio < Control::Logic


	def on_load
		self[:power] = Off
		register(:Camera_1, :error)	# expects camera_1_error_changed
		#register(:Camera_1, :error)	# expects camera_1_error_changed
		register(:Lifter_1, :error)	# expects camera_1_error_changed
		#register(:Camera_1, :error)	# expects camera_1_error_changed
	end


	LIGHTING = {
		:day => {			# afternoon
			:pos1 => {
				1 => 22,
				2 => 18,
				3 => 10,
				4 => 15,
				5 => 26,
				6 => 38
			},
			:pos2 => {
				1 => 1,
				2 => 33,
				3 => 13,
				4 => 45,
				5 => 29,
				6 => 40
			},
			:tv => {
				1 => 42,
				2 => 43,
				3 => 49,
				4 => 8,
				5 => 50,
				6 => 9
			}
		},
		:night => {
			:pos1 => {
				1 => 23,
				2 => 20,
				3 => 47,
				4 => 17,
				5 => 30,
				6 => 36
			},
			:pos2 => {
				1 => 4,
				2 => 32,
				3 => 12,
				4 => 44,
				5 => 27,
				6 => 39
			},
			:tv => {
				1 => 42,
				2 => 43,
				3 => 49,
				4 => 8,
				5 => 50,
				6 => 9
			}
		}
	}

	CAMERA = {
		:day => {
			:pos1 => {
				:standing => {
					1 => 1,
					2 => 2,
					3 => 3,
					4 => 4,
					5 => 5,
					6 => 6
				},
				:sitting => {
					1 => 11,
					2 => 12,
					3 => 13,
					4 => 14,
					5 => 15,
					6 => 16
				}
			},
			:pos2 => {
				:standing => {
					1 => 1,
					2 => 2,
					3 => 3,
					4 => 4,
					5 => 5,
					6 => 6
				},
				:sitting => {
					1 => 11,
					2 => 12,
					3 => 13,
					4 => 14,
					5 => 15,
					6 => 16
				}
			},
			:tv => {
				1 => 41,
				2 => 42,
				3 => 43,
				4 => 44,
				5 => 45,
				6 => 46
			}
		},
		:night => {
			:pos1 => {
				:standing => {
					1 => 21,
					2 => 22,
					3 => 23,
					4 => 24,
					5 => 25,
					6 => 26
				},
				:sitting => {
					1 => 31,
					2 => 32,
					3 => 33,
					4 => 34,
					5 => 35,
					6 => 36
				}
			},
			:pos2 => {
				:standing => {
					1 => 21,
					2 => 22,
					3 => 23,
					4 => 24,
					5 => 25,
					6 => 26
				},
				:sitting => {
					1 => 31,
					2 => 32,
					3 => 33,
					4 => 34,
					5 => 35,
					6 => 36
				}
			},
			:tv => {
				1 => 41,
				2 => 42,
				3 => 43,
				4 => 44,
				5 => 45,
				6 => 46
			}
		}
	}


	LIFTER = {
		:standing => {
			:pos1 => {
				1 => 1,
				2 => 2,
				3 => 3,
				4 => 4,
				5 => 5,
				6 => 6
			},
			:pos2 => {
				1 => 1,
				2 => 2,
				3 => 3,
				4 => 4,
				5 => 5,
				6 => 6
			},
			:tv => {
				1 => 1,
				2 => 2,
				3 => 3,
				4 => 4,
				5 => 5,
				6 => 6
			}
		},
		:sitting => {
			:pos1 => {
				1 => 11,
				2 => 12,
				3 => 13,
				4 => 14,
				5 => 15,
				6 => 16
			},
			:pos2 => {
				1 => 11,
				2 => 12,
				3 => 13,
				4 => 14,
				5 => 15,
				6 => 16
			},
			:tv => {
				1 => 1,
				2 => 2,
				3 => 3,
				4 => 4,
				5 => 5,
				6 => 6
			}
		}
	}


	def do_preset(position, preset, posture = 'standing')	# or sitting
		system[:Audio].call_preset(8)		# unmute all
		system[:Audio].call_preset(preset)	# Preset for current position
		system[:Lighting].smart_on(2)		# All off

		now = Time.now
		day_start = Time.local(now.year, now.month, now.day, 6, 30)
		day_end = Time.local(now.year, now.month, now.day, 18, 30)

		if now > day_start && now < day_end
			now = :day
		else
			now = :night
		end

		posture = posture.to_sym if posture.class == String

		logger.debug "Calling Pos:#{position}, #{posture}, preset #{preset}"

		if position == 1
			system[:Switcher].switch(:sdi_3_in => :pgm)	# SDI 3 == Camera 1
			system[:Lighting].smart_on(LIGHTING[now][:pos1][preset])
			
			system[:Camera_1].preset(CAMERA[now][:pos1][posture][preset])
			system[:Lifter_1].preset(LIFTER[posture][:pos1][preset])
		else
			system[:Switcher].switch(:sdi_4_in => :pgm)	# SDI 4 == Camera 2

			if position == 2
				system[:Camera_2].preset(CAMERA[now][:pos2][posture][preset])
				system[:Lighting].smart_on(LIGHTING[now][:pos2][preset])
				system[:Lifter_2].preset(LIFTER[posture][:pos2][preset])
			else
				system[:Camera_2].preset(CAMERA[now][:tv][preset])
				system[:Lighting].smart_on(LIGHTING[now][:tv][preset])
				system[:Lifter_2].preset(LIFTER[posture][:tv][preset])
				system[:TouchScreen].power(On)
				system[:TouchScreen].switch_to(:hdmi)
			end
		end
	end


	def shutdown
		self[:power] = Off

		#system[:Audio].call_preset(7)			# Mute all
		#system[:Switcher].switch(:colour_bar => :pgm)	# No need to do this
		#system[:Camera_1].power(Off)			# We shouldn't do this

		system[:Monitor_1].power(Off)
		system[:Monitor_2].power(Off)
		system[:Lighting].smart_on(2)			# All off
		system[:IP_Link].set_relay(3, Off)		# Physical on air off

		#
		# SMX Matrix
		## Hide the on air sign!
		## system[:Switcher_2].switch_video({0 => [2, 3]}, 1) # Mute is preferred
		#
		system[:Switcher_2].mute_video([2, 3], 1)
		#system[:Display_2].switch_to(:tv)		# Near window on camera 1 side
		#system[:Display_3].switch_to(:tv)		# (Temporary)
		#system[:Display_4].switch_to(:tv)
		
		
		system[:Display_1].power_on? do |result|
			if result == Off
				system[:Display_1].power(On)
			end
			system[:Display_1].switch_to(:tv)
		end


		#
		# Restore tv table audio (it may have been turned off)
		#
		system[:Audio_2].unmute_input(1)
		system[:Audio_2].unmute_input(2)
		system[:Switcher_3].switch_to(3)	# Switch to PC
	end

	def power_up
		self[:power] = On

		system[:Audio].call_preset(8)			# Un-mute all mics
		system[:Audio_2].mute_input(1)			# Mute tv table audio
		system[:Audio_2].mute_input(2)
		system[:Audio_2].mute_input(3)
		system[:Audio_2].mute_input(4)
		system[:Switcher_3].switch_to(3)		# Switch to PC

		#system[:Switcher].switch(:colour_bar => :pgm)
		system[:Switcher].switch(:sdi_3_in => :pgm)
		system[:Camera_1].power(On)
		system[:Camera_2].power(On)
		system[:Monitor_1].power(On)
		system[:Monitor_2].power(On)
		system[:Monitor_1].switch_to(:sdi1)
		system[:Monitor_2].switch_to(:sdi1)
		system[:IP_Link].set_relay(3, On)		# Physical on air on

		
		#
		# SMX Matrix
		## Show the on air sign!
		#
		system[:Switcher_2].switch_video({3 => [2, 3]}, 1)
		system[:Switcher_2].unmute_video([2, 3], 1)
		
		system[:Display_1].switch_to(:hdmi)
		#system[:Display_2].switch_to(:hdmi) # (Temporary until logo insert)
		#system[:Display_3].switch_to(:hdmi)
		#system[:Display_4].switch_to(:hdmi)
	end


	
	CHANNELS = {
		:abc_1 => 2,
		:channel_7 => 7,
		:channel_9 => 9,
		:channel_10 => 10,
		:abc_news_24 => 24,
		:sky_news => 350,
		:sky_business => 351,
		:bloomberg => 354,
		:cnn => 355,
		:cnbc => 356,
		:bbc_global_news => 361
	}
	
	def present_to(channel)
		channel = channel.to_sym if channel.class == String
		
		system[:Display_1].power_on? do |result|
			if result == Off
				system[:Display_1].power(On)
			end
			system[:Display_1].channel(CHANNELS[channel])
		end
	end
	
	
	
	def camera_1_error_changed(data)
		Notifier.alert(system, "Camera 1 Error", "Error #{data[0]}: #{data[1]} has occured on camera 1\nIt may no longer be functional").deliver
	end

	def camera_2_error_changed(data)
		Notifier.alert(system, "Camera 2 Error", "Error #{data[0]}: #{data[1]} has occured on camera 2\nIt may no longer be functional").deliver
	end

	def lifter_1_error_changed(data)
		Notifier.alert(system, "Lifter 1 Error", "#{data} has occured on lifter 1\nIt may no longer be functional").deliver
	end

	def lifter_2_error_changed(data)
		Notifier.alert(system, "Lifter 2 Error", "#{data} has occured on lifter 2\nIt may no longer be functional").deliver
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


# Switcher_2 (SMX Matrix)
# -----------------------
## Plane: usb 0, hdmi 1
## input 3 outputs 2 + 3 == on air displays + computer
## input 2 == computer