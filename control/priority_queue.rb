module Control
	
	#
	# Must only be accessed on the reactor thread
	#
	class PriorityQueue
		def initialize *args
			@next = []
			@queues = {}
		end
		
		def push(obj, priority = 0)
			@next << priority
			@next.sort!
			@queues[priority] = Queue.new if @queues[priority].nil?
			@queues[priority].push(obj)
		end
		
		def pop
			return @queues[@next.shift].pop(true)
		end
		
		def length
			return @next.length
		end
		
		def empty?
			return @next.empty?
		end
	end

end