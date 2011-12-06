

module Control
	def self.print_error(logger, e, options = {})

		begin
			level = options[:level] || Logger::INFO
			logger.add(level) do
				message = options[:message].nil? ? "" : "%p" % options[:message]
				message += "\n#{e.message}"
				e.backtrace.each {|line| message += "\n#{line}"}
				message
			end
		rescue
		end

	end
	
	class TimerWrapper
		def initialize(ref = nil, &block)
			@reference = ref
			@callback = block
		end
		
		def reference=(ref)
			@reference = ref if @reference.nil?
		end
		
		def interval
			if @reference.respond_to?(:interval)
				return @reference.interval
			end
			return nil
		end
		
		def interval=(time)
			if @reference.respond_to?(:interval)
				@reference.interval = time
			end
		end
		
		def cancel
			if @reference.present?
				@reference.cancel
				@reference = nil
			end
			if @callback.present?
				@callback.call(self)
				@callback = nil
			end
		end
	end
	
	module Utilities
		#
		# Converts a hex encoded string into a raw byte string
		#
		def hex_to_byte(data)	# Assumes string - converts to binary string
			data.gsub!(/(0x|[^0-9A-Fa-f])*/, "")				# Removes invalid characters
			output = ""
			data = "0#{data}" if data.length % 2 > 0
			data.scan(/.{2}/) { |byte| output << byte.hex}	# Breaks string into an array of characters
			return output
		end
		
		#
		# Converts a raw byte string into a hex encoded string
		#
		def byte_to_hex(data)	# Assumes string - converts from a binary string
			output = ""
			data.each_byte { |c|
				s = c.to_s(16)
				s = "0#{s}" if s.length % 2 > 0
				output << s
			}
			return output
		end
		
		#
		# Converts a string into a byte array
		#
		def str_to_array(data)
			data.bytes.to_a
		end
		
		#
		# Converts an array into a raw byte string
		#
		def array_to_str(data)
			data.pack('c*')
		end
		
		#
		# Creates a new threaded task
		#
		def task(callback = nil, &block)
			EM.defer(nil, callback) do
				begin
					block.call
				rescue => e
					Control.print_error(System.logger, e, :message => "Error in task")
				end
			end
		end
		
		
		#
		# runs an event every so many seconds
		#
		def periodic_timer(time, &block)
			timer = EM::PeriodicTimer.new(time) do
				EM.defer do
					begin
						block.call
					rescue => e
						Control.print_error(System.logger, e, :message => "Error in periodic timer")
					end
				end
			end
			
			#
			# Check if we are an instance of device or logic
			#
			if (self.class.ancestors & [Control::Device, Control::Logic]).length > 0
				@status_lock.synchronize {
					@active_timers = @active_timers || [].extend(MonitorMixin)
				}
				
				timer = TimerWrapper.new(timer) do |timer|
					@active_timers.synchronize {
						@active_timers.delete(timer)
					}
				end
				
				@active_timers.synchronize {
					@active_timers << timer
				}
			end
			return timer
		end
		
		#
		# Runs an event once after a particular amount of time
		#
		def one_shot(time, &block)
			
			#
			# Check if we are tracking timers 
			#
			capture_timer = (self.class.ancestors & [Control::Device, Control::Logic]).length > 0
			if capture_timer
				timer = nil
				@status_lock.synchronize {
					@active_timers = @active_timers || [].extend(MonitorMixin)
				}
				
				timer = TimerWrapper.new(timer) do |timer|
					@active_timers.synchronize {
						@active_timers.delete(timer)
					}
				end
				
				@active_timers.synchronize {
					@active_timers << timer
				}
				
				rem_proc = Proc.new  { |timer|
					@active_timers.synchronize {
						@active_timers.delete(timer)
					}
				}
			end
			
			#
			# Create the timer
			#
			ref = EM::Timer.new(time) do
				EM.defer do
					begin
						rem_proc.call(timer) unless rem_proc.nil?
						block.call
					rescue => e
						Control.print_error(System.logger, e, :message => "Error in one shot (or shutting down)")
					end
				end
			end
			
			#
			# return the reference
			#
			if timer.nil?
				timer = ref
			else
				timer.reference = ref
			end
			
			return timer
		end
		
		
		#
		# Makes functions private when included in a class
		#
		module_function :hex_to_byte
		module_function :byte_to_hex
		module_function :str_to_array
		module_function :array_to_str
		
		module_function :task
		module_function :periodic_timer
		module_function :one_shot
	end
end