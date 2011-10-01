class User < ActiveRecord::Base
	belongs_to	:auth_source
	has_many	:user_groups, :dependent => :destroy
	has_many	:groups,	:through => :user_groups
	
	
	#
	# This is used for local authentication
	#	Creates an authenticate(password) method on a user instance
	#
	has_secure_password
	validates_presence_of :password, :on => :create
	
	
	def self.try_to_login(login, password, source)
		# Make sure no one can sign in with an empty password
		return nil if password.blank? || login.blank? || source.nil?
		
		#
		# Try and login the user
		#
		user = nil
		begin
			logger.debug "Authenticating '#{login}' against '#{source.name}'" if logger.debug?
			user = source.authenticate(login, password)
		rescue => e
			logger.error "Error during authentication: #{e.message}"
		end
		return user
	end
	
	
	protected
	
	
	validates_presence_of :identifier, :auth_source
end

#
# Mix in any project specific code
#
User.class_eval &Login.user_mixin unless Login.user_mixin.nil?
