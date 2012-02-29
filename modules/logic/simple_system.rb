class SimpleSystem < Control::Logic


	def show_and_hear(projector, input)
		system[projector].lamp_on? do |result|
			if result == Off
				system[projector].lamp(On)
			end
			system[projector].switch_to(input.downcase)
		end
	end


end