require 'json'

class PodInterface < Control::Logic		
	module AMXInterface
		def post_init
			begin
				#
				# Someone connected -- check they are valid
				#
				@serialise = Mutex.new
				@waitlock = Mutex.new
				@cv = ConditionVariable.new
				port, ip = Socket.unpack_sockaddr_in(get_peername)
				Control::System.logger.info "AMX POD Interface -- connection from: #{ip}"
			rescue => e
				Control.print_error(Control::System.logger, e, {
					:message => "module PodInterface error starting connection",
					:level => Logger::ERROR
				})
			end
		end
	
		def receive_data(data)
			begin
				(@buffer ||= BufferedTokenizer.new('' << 0x03)).extract(data).each do |line|
					line = line.split("" << 0x02)
					if line.length >= 2
						
						process_command(line[-1])
						
					end
				end
			rescue => e
				EM.defer do
					Control.print_error(Control::System.logger, e, {
						:message => "module PodInterface error extracting data",
						:level => Logger::ERROR
					})
				end
			end
		end
		
		protected
		
		def process_command(line)
			EM.defer do
				@serialise.synchronize {
					begin
						line = JSON.parse(line, {:symbolize_names => true})
						
						#
						# Process commands here
						#
						systems = Zone.where(:name => line[:control]).first.control_systems
						@count = 0
						@total = systems.count
						failed = false
						
						if not line[:presentation].nil?
							systems.each do |pod|
								EM.defer do
									begin
										Control::System[pod.name][:Pod].enable_sharing(line[:presentation])
									rescue => e
										Control.print_error(Control::System.logger, e, {
											:message => "module PodInterface error enabling presentation on pod #{pod.name}",
											:level => Logger::WARN
										})
									ensure
										@waitlock.synchronize {
											@count += 1
											if @count == @total
												@cv.signal
											end
										}
									end
								end
							end
						elsif not line[:override].nil?
							systems.each do |pod|
								EM.defer do
									begin
										Control::System[pod.name][:Pod].do_share(line[:override])
									rescue => e
										Control.print_error(Control::System.logger, e, {
											:message => "module PodInterface error overriding pod #{pod.name}",
											:level => Logger::WARN
										})
									ensure
										@waitlock.synchronize {
											@count += 1
											if @count == @total
												@cv.signal
											end
										}
									end
								end
							end
						else
							failed = true
							send_data("" << 0x02 << JSON.generate({'result' => false}) << 0x03)
						end
						
						if not failed
							@waitlock.synchronize {
								if @count != @total
									@cv.wait(@waitlock)
								end
							}
							send_data("" << 0x02 << JSON.generate({'result' => true}) << 0x03)
						end
						
					rescue => e
						Control.print_error(Control::System.logger, e, {
							:message => "module PodInterface error processing AMX command",
							:level => Logger::ERROR
						})
						begin
							send_data("" << 0x02 << JSON.generate({'result' => 'server error'}) << 0x03)
						rescue
						end
					ensure
						ActiveRecord::Base.clear_active_connections!
					end
				}
			end
		end
	end

	def on_load
		@server = EventMachine::start_server '0.0.0.0', 24842, AMXInterface
		logger.info "AMX POD Interface started"
	end
	
	
	def on_unload
		EventMachine::stop_server(@server) unless @server.nil?
		logger.info "AMX POD Interface stopped"
	end
	
	
	def on_update
		EventMachine::stop_server(@server) unless @server.nil?
		@server = EventMachine::start_server '0.0.0.0', 24842, AMXInterface
		logger.info "AMX POD Interface reloaded"
	end
end
