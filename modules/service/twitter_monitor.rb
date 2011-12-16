
class TwitterMonitor < Control::Service
	MAX_WAIT = 240

	def on_load
		@failures = 0
		start_streaming
	end
	
	def on_unload
		
	end
	
	
	#
	# Assign a connection middle ware
	#
	def use_middleware(connection)
		connection.use EventMachine::Middleware::JSONResponse
		connection.use EventMachine::Middleware::OAuth, @oauth_config
		connection.use HttpDebugInspector if logger.debug?
	end
	
	#
	# Twitter data recieved
	#
	def received(chunk, command)
		logger.info "Twitter returned #{chunk.inspect}"
	end
	
	
	protected
	
	
	def load_config
		@oauth_config = {
			:consumer_key			=> setting(:consumer_key),
			:consumer_secret		=> setting(:consumer_secret),
			:access_token			=> setting(:access_token),
			:access_token_secret	=> setting(:access_token_secret)
		}
		@follow = JSON.parse(setting(:follow))
		
		logger.debug "Twitter settings:"
		logger.debug "-- following: #{@follow.inspect}"
		logger.debug "-- config: #{@oauth_config.inspect}"
	end
	
	
	def start_streaming
		load_config
		request('/1/statuses/filter.json', {
			:verb => :post,
			:stream => true,
			:keepalive => false,
			:stream_closed => proc { |http|
				logger.info "Twitter connection failed: #{http.error}"
				@failures += 1
				if @failures > 1
					wait = 20 * (@failures - 1)
					if wait > MAX_WAIT
						wait = MAX_WAIT
					end
					one_shot wait do
						start_streaming
					end
				else
					start_streaming
				end
			},
			:headers => proc { |headers|
				@failures = 0
				logger.info "Twitter returned #{headers.inspect}"
			},
			:connect_timeout => 5,
			:inactivity_timeout => 90,
			:body => {:follow => @follow.join(",")}
		})
	end
end