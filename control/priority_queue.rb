module Control

	class PriorityQueue
		def initialize *args
			@next = []
			@queues = {}
			@mutex = Mutex.new
		end
		
		def push(obj, priority = 0)
			@mutex.synchronize {
				@next << priority
				@next.sort!
				@queues[priority] = Queue.new if @queues[priority].nil?
				@queues[priority].push(obj)
			}
		end
		
		def pop
			@mutex.synchronize {
				return @queues[@next.shift].pop(true)	# non-blocking
			}
		end
		
		def length
			@next.length
		end
		
		def empty?
			@next.empty?
		end
	end

end