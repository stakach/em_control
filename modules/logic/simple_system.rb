class SimpleSystem < Control::Logic


	def show_and_hear(projector, input)
		if !system[projector].lamp_on?
			system[projector].lamp(On)
		end
		system[projector].switch_to(input.downcase)
	end


end