class AuthSourceLocal < AuthSource
	
	def authenticate(login, password)
		return nil if login.blank? || password.blank?
		
		user = User.where('auth_source_id = ? AND identifier = ?', self.id, login).first
		if user && user.authenticate(password)
			user.login_count += 1
			user.save!
			return user
		else
			return nil
		end
	end
	
	def auth_method_name
		'LOCAL'
	end
end