#
# Code by Davy Brion
#	http://davybrion.com/blog/2010/08/using-more-rubyesq-events-in-ruby/
#

class Event
	attr_reader :name
 
	def initialize(name)
		@name = name
		@handlers = []
	end
 
	def add(method=nil, &block)
		@handlers << method if method
		@handlers << block if block
	end
 
	def remove(method)
		@handlers.delete method
	end
 
	def trigger(*args)
		@handlers.each { |handler| handler.call *args }
	end
end

module EventPublisher
	def subscribe(symbol, method=nil, &block)
		event = send(symbol)
		event.add method if method
		event.add block if block
	end
 
	def unsubscribe(symbol, method)
		event = send(symbol)
		event.remove method
	end
 
	private
 
	def trigger(symbol, *args)
		event = send(symbol)
		event.trigger *args
	end
 
	self.class.class_eval do
		def event(symbol)
			getter = symbol
			variable = :"@#{symbol}"
 
			define_method getter do
				event = instance_variable_get variable
 
				if event == nil
					event = Event.new(symbol.to_s)
					instance_variable_set variable, event
				end
 
				event
			end
		end
	end
end
