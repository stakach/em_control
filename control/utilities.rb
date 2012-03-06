

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
	
	class JobProxy
		
		instance_methods.each { |m| undef_method m unless m =~ /(^__|^send$|^object_id$)/ }
		
		def initialize(jobs, index, lock)
			@jobs = jobs
			@index = index
			@job = @jobs[@index]	# only ever called from within the lock
		end
		
		
		def unschedule
			EM.schedule do
				begin
					@job.unschedule
					@jobs.delete(@index)
				rescue
				end
			end
		end
		
		protected
		
		def method_missing(name, *args, &block)
			EM.schedule do
				@job.send(name, *args, &block)
			end
		end
	end
	
	class ScheduleProxy
		
		instance_methods.each { |m| undef_method m unless m =~ /(^__|^send$|^object_id$)/ }
		
		def initialize
			@jobs = {}
			@index = 0
		end
		
		def clear_jobs
			EM.schedule do
				@jobs.each_value do |job|
					job.unschedule
				end
				
				@jobs = {}
				@index = 0
			end
		end
		
		protected
		
		def method_missing(name, *args, &block)
			EM.schedule do
				begin
					if block.present?
						job = nil
						
						if [:in, :at].include?(name)
							index = @index				# local variable for the block
							
							job = Control::scheduler.send(name, *args) do
								begin
									block.call
								rescue => e
									Control.print_error(System.logger, e, :message => "Error in one off scheduled event")
								ensure
									EM.schedule do
										@jobs.delete(index)
									end
								end
							end
						else
							job = Control::scheduler.send(name, *args) do
								begin
									block.call
								rescue => e
									Control.print_error(System.logger, e, :message => "Error in repeated scheduled event")
								end
							end
						end
						
						if job.present?
							@jobs[@index] = job
							job = JobProxy.new(@jobs, @index, @job_lock)
							
							@index += 1
							
							return job
						end
						
						return nil
					else
						Control::scheduler.send(name, *args, &block)
					end
				rescue
				end
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
		# Schedule events
		#
		def schedule
			return @schedule unless @schedule.nil?
			@status_lock.synchronize {
				@schedule ||= ScheduleProxy.new
			}
        end
		
		
		#
		# Makes functions private when included in a class
		#
		module_function :hex_to_byte
		module_function :byte_to_hex
		module_function :str_to_array
		module_function :array_to_str
		
		module_function :schedule
		module_function :task
	end
end