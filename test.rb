require 'rubygems'
require 'eventmachine'


class Devices
	@@device = []

	def self.device
		@@device
	end

	def self.<< (device)
		@@device << device
	end
end


class Device < EventMachine::Connection

	PRI_QUEUE = 0
	REG_QUEUE = 1

	DATA  = 0
	WAIT  = 1
	RETRY = 2

	def initialize *args
		super

		@recieve_queue = Queue.new

		@recieve_lock = Mutex.new
		@send_lock = Mutex.new  # For in sync send and recieves when required
		
		@send_queues = [Queue.new, Queue.new]
		@last_command = [nil, nil]
		
		Devices << self

	rescue Exception => e

		p "init error!" + e.message

	end


	def post_init
		# Add to class variable
	end

	
	def connection_completed
		# set status
		
		operation = proc { self.connected }
		EM.defer(operation) if self.respond_to?(:connected)
	end

  
	def receive_data(data)
		@recieve_queue.push(data)

		operation = proc { self.process_data }
		EM.defer(operation)
	end


	def unbind
		# set offline
		# attempt re-connect

		operation = proc { self.disconnected }
		EM.defer(operation) if self.respond_to?(:disconnected)
	end



	#
	# Using EM Queue which schedules tasks in order
	#
	def send(data, queue = REG_QUEUE, wait = true, maxRetries = 2)
		@send_lock.synchronize {		# Ensure queue order and queue sizes

			@send_queues[queue].push([data,wait,maxRetries])
			
			waitingResponse = @last_command[REG_QUEUE].nil? ? false : @last_command[REG_QUEUE][WAIT]
			
			if !waitingResponse
				@last_command[queue] = [data,wait,maxRetries]
				process_send
			end
		}
	end
	
	
	#
	# Function for user code
	#
	def last_command(queue = REG_QUEUE)
		return @last_command[queue].nil? ? nil : @last_command[queue][DATA]
	end


	protected


	#
	# Controls the flow of data for retry puropses
	#
	def process_data
		succeeded = nil

		if self.respond_to?(:recieved)
		
		
			@recieve_lock.synchronize {			# Lock ensures that serialisation of events per-device module
				succeeded = recieved(@recieve_queue.pop(true))	# non-blocking call (will crash if there is no data)

				@send_lock.synchronize {		# recieved call can call send so must sync here
					if succeeded == false
						if @send_queues[PRI_QUEUE].length == 0 && @last_command[REG_QUEUE][RETRY] > 0
							@last_command[REG_QUEUE][RETRY] -= 1
							@send_queues[PRI_QUEUE].push(@last_command[REG_QUEUE])
							
							process_send
						elsif @send_queues[PRI_QUEUE].length > 0
							process_send
						else
							next_command
						end
					elsif succeeded == true
						next_command
					end
				}
			}
			
			
		else
			@recieve_queue.pop(true)
			@send_lock.synchronize {
				next_command
			}
		end
	#rescue	# incase a queue has been modified by user code we don't want to crash a thread
	#	p "rescue"
	#	@send_lock.synchronize {
	#		next_command
	#	}
	end


	private
	
	
	def next_command
		if @send_queues[PRI_QUEUE].length > 0 || @send_queues[REG_QUEUE].length > 0
			process_send
		else
			@last_command[REG_QUEUE][WAIT] = false
		end
	end


	def process_send
		queue = if  @send_queues[PRI_QUEUE].length > 0
			PRI_QUEUE
		else
			REG_QUEUE
		end
		
		data = @send_queues[queue].pop(true)
		@last_command[queue] = data

		EM.schedule proc {
			send_data(data[DATA])
		}
	end
end



#
# Will reside in user defined file
#
class NECProj < Device
	def connected
		send('connection made')
		Devices.device[0].command1
		Devices.device[0].command2
		Devices.device[0].command1
		Devices.device[0].command3
		Devices.device[0].command1

		EM.add_timer 3, proc { EM.stop_event_loop }
	end


	def recieved(data)
		p data
		
		if data =~ /fail/i
			p "-> #{last_command}"
			if last_command =~ /criticalish/i
				send('recovery ping', PRI_QUEUE)	# pri-queue ensures that this is run before the next standard item
				send('criticalish ping', PRI_QUEUE)
			end
			return false
		end
		
		return true # Return true if command success, nil if not complete, false if fail
	end
	
	
	def command1
		send('test ping')
	end
	
	
	def command2
		send('critical ping')
	end
	
	def command3
		send('criticalish ping')
	end


	def disconnected
		p 'disconnected...'
	end
end


#
# Will be controlled in our launch program
#
EventMachine.run do
	EM.connect "127.0.0.1", 8081, NECProj
end
