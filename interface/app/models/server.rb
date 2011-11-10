class Server < ActiveRecord::Base
	#
	# When converting to json don't include the root element (:Server => {})
	#
	self.include_root_in_json = false
		
	
	protected
	
	
	validates_presence_of :hostname, :online
end
