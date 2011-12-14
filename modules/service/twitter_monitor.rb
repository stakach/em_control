class TwitterMonitor < Control::Service

	def on_load
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
	end
	
	#
	# Twitter data recieved
	#
	def recieved(chunk, command)
		logger.info chunk.inspect
	end
	
	
	protected
	
	
	def load_config
		@oauth_config = {
			:consumer_key			=> setting(:consumer_key),
			:consumer_secret		=> setting(:consumer_secret),
			:access_token			=> setting(:access_token),
			:access_token_secret	=> setting(:access_token_secret)
		}
	end
	
	
	def start_streaming
		load_config
		request('/1/statuses/filter.json', {
			:stream => true,
			:stream_closed => proc {
				start_streaming
			}
		})
	end
end