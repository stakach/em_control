module Control
	
	class ResolverPool
		
		def initialize(size = 30)
			
			@size = size
			@jobs = Queue.new
			
			@pool = Array.new(@size) do |i|
				
				Thread.new do
					#Thread.current[:id] = i
					Thread.current.priority = Thread.current.priority - 1
					loop do
						begin
							job = @jobs.pop
							job.resolve
						rescue => e
							#
							# Print error here
							#
						end
					end
				end
				
			end
			
		end
		
		def schedule(job)
			@jobs << job
		end
	
	end
	
	
	class ResolverJob
		
		include EM::Deferrable
		
		def initialize(hostname)
			if IPAddress.valid? hostname
				self.succeed(hostname)
			else
				@hostname = hostname
				
				#
				# Enter self into resolver queue
				#
				if EM.reactor_thread?
					EM.defer do
						Control.resolver.schedule(self)
					end
				else
					Control.resolver.schedule(self)
				end
			end
		end
		
		def resolve 
			begin
				ip = Resolv.getaddress(@hostname)
				EM.schedule do
					self.succeed(ip)
				end
			rescue => e
				EM.schedule do
					self.fail(e)
				end
			end
		end
		
	end

end