class User < ActiveRecord::Base
	belongs_to	:auth_source
	
	
	def self.try_to_login(login, password)
		# Make sure no one can sign in with an empty password
		return nil if password.to_s.empty?
		user = User.where("LOWER(identifier) LIKE ?", '%' + login.downcase + '%').first
		attrs = nil
		if user
			# user is already in local database
			return nil if !user.active?
			attrs = user.auth_source.authenticate(login, password)
			return nil unless attrs
			user.touch
			attrs.merge!(:login => user.id)
		else
			# user is generic, try to authenticate with available sources
			attrs = AuthSource.authenticate(login, password)
			return nil unless attrs
			
			query = ""
			members = []
			attrs[:member_of].each do |member|
				if !member.strip.empty?		# ensure there is a membership - empty strings are bad
					if query.empty?
						query += "identifier = ? OR identifier LIKE ?"
					else
						query += " OR identifier = ? OR identifier LIKE ?"
					end
					members << member << (member + ',%')	# the comma here avoids security risks
				end
			end
			user = User.where(query, *members).first unless query.empty?
			
			if user && user.active?
				attrs.merge!(:login => user.id)
			else
				return nil
			end
		end
		
		return attrs
	rescue => text
		return nil
	end
	
	
	protected
	
	
	validates_presence_of :identifier, :auth_source
end

#
# Mix in any project specific code
#
User.class_eval &Login.user_mixin unless Login.user_mixin.nil?
