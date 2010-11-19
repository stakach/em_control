require 'fiber'

def callcc(proc, *args)
	Fiber.new do
		proc.call(*args) { |*yargs| Fiber.yield(*yargs) }
	end.resume
end

def projector?
	return true
end


a = "new"
p a
a = callcc((method :projector?))
p a
