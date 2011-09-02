require "login/engine"

module Login
	
	def self.redirection(&block)
		@redirect_to = block if block
		@redirect_to
	end
	def self.redirection=(proc)
		@redirect_to = proc
	end
	
	
	def self.user_mixin(&block)
		@user_mixin = block if block
		@user_mixin
	end
	
end
