class StrandVisionNet < Control::Device
	
	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:wait => false
		}
	end
	
	
	
	def connected
		@polling_timer = periodic_timer(30) do
			logger.debug "-- Polling Lighting"
			set_mode(0, :priority => 99)		# We need to maintain the connection
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	
	#
	# Start / Learn preset
	## Preset
	# => Preset (1 - 32) [0 = off]
	#
	def start(preset, room = 1, rate = 0)
		send("SP #{room.to_s.rjust(3, '0')} #{preset.to_s.rjust(2, '0')} #{rate.to_s.rjust(2, '0')}\r")
	end
	
	def learn(preset, room = 1)
		send("LP #{room.to_s.rjust(3, '0')} #{preset.to_s.rjust(2, '0')}\r")
	end
	
	
	def toggle(channel, direction, room = 1)
		direction = direction.to_sym if direction.class == String
		
		if direction == :down
			send("TD #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')}\r")
		else
			send("TU #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')}\r")
		end
	end
	
	def slider(channel, level, room = 1)
		send("SL #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')} #{level.to_s.rjust(3, '0')}\r")
	end
	
	def submaster(index, room = 1)
		send("LS #{room.to_s.rjust(3, '0')} #{index.to_s.rjust(2, '0')}\r")
	end
	
	def manual(room, master, *levels)
		levelstring = ""
		levels.each do |level|
			levelstring << " #{level.to_s.rjust(3, '0')}"
		end
		send("MN #{room.to_s.rjust(3, '0')} #{master.to_s.rjust(3, '0')}#{levelstring}\r")
	end
	
	def expander(group, room = 1, channel = nil, *levels)
		if channel.nil?
			send("EG #{room.to_s.rjust(3, '0')} #{group.to_s.rjust(2, '0')}\r")
		else
			levelstring = ""
			levels.each do |level|
				levelstring << " #{level.to_s.rjust(3, '0')}"
			end
			send("EG #{room.to_s.rjust(3, '0')} #{group.to_s.rjust(2, '0')} #{channel.to_s.rjust(2, '0')}#{levelstring}\r")
		end
	end
	
	#
	# Raise / Lower / Stop raise or lower
	## Coded Channel
	# => 0: Reserved
	# => 1 - 127: Channels 1 to 127
	# => 128: All Channels in room
	# => 129 - 255: Channel in Preset: 1 - 126
	# => 255 current preset channels
	#
	def raise(channel, room = 1)	# coded channel
		send("RA #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')}\r")
	end
	
	def lower(channel, room = 1)	# coded channel
		send("LW #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')}\r")
	end
	
	def stop_rl(channel, room = 1)	# coded channel
		send("ST #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')}\r")
	end
	
	
	def record(room, master, preset, *levels)
		levelstring = ""
		levels.each do |level|
			levelstring << " #{level.to_s.rjust(3, '0')}"
		end
		send("RB #{room.to_s.rjust(3, '0')} #{preset.to_s.rjust(2, '0')} #{master.to_s.rjust(3, '0')}#{levelstring}\r")
	end
	
	
	def room_link(clear, *rooms)
		if [true, 0].include?(clear)
			clear = 0
		else
			clear = 1
		end
		
		roomstring = ""
		rooms.each do |room|
			roomstring << " #{room.to_s.rjust(3, '0')}"
		end
		
		send("DR #{clear}#{roomstring}\r")
	end
	
	
	def submaster_level(level, index, room = 1)
		send("SB #{room.to_s.rjust(3, '0')} #{index.to_s.rjust(2, '0')} #{level.to_s.rjust(3, '0')}\r")
	end
	
	
	def take_control(room, master, *levels)
		levelstring = ""
		levels.each do |level|
			levelstring << " #{level.to_s.rjust(3, '0')}"
		end
		send("TC #{room.to_s.rjust(3, '0')} #{master.to_s.rjust(3, '0')}#{levelstring}\r")
	end
	
	# Unknown parameter rr
	#def set_channel(channel, level, room = 1, rr)
	#	send("SC #{room.to_s.rjust(3, '0')} #{channel.to_s.rjust(3, '0')} #{level.to_s.rjust(3, '0')}\r")
	#end
	
	def set_mode(id, options = {})
		send("SM #{id.to_s.rjust(2, '0')}\r", options)
	end
	
	
	#
	# Interface
	#
	def lock(button)
		send("LB idd #{button}\r")
	end
	
	def unlock(button)
		send("UB idd #{button}\r")
	end
	
	def smart_on(id)
		send("SN idd #{id}\r")
	end
	
	def smart_off(id)
		send("SF idd #{id}\r")
	end
	
	def send_mimic(button, action)
		if [On, :down, :on, 1].include?(action)
			action = 1
		else
			action = 0
		end
		send("MC idd #{button} #{action}\r")
	end
	
	def console_button(id, action)
		if [:down, 0].include?(action)
			action = 0
		else
			action = 1
		end
		send("CB idd #{id} #{action}\r")
	end
	
	def console_led(id, action)
		if [Off, :off, 0].include?(action)
			action = 0
		else
			action = 1
		end
		send("CL idd #{id} #{action}\r")
	end
	
	
	#
	# Don't know what, if any, data is returned
	#
	def received(data, command)
		logger.debug "Strand lighting sent #{data}"
	end
	
end