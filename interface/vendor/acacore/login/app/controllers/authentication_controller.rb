class AuthenticationController < ActionController::Base	# Base to seperate from application controller
	protect_from_forgery
	
	layout 'login'
	
	
	def start
		if !session[:user].nil?
			login_success
		end
	end
	
	
	def login
		authenticate
		
		if @user.nil?
			flash[:notice] = t(:login_error)
			render :action => 'start'
		else
			#Perform redirect (application defined)
			login_success
		end
	end
	
	
	def logout
		reset_session
		flash[:notice] = t(:login_logout)
		redirect_to root_path
	end
	
	
	
	#
	# Change password
	#
	def edit
		authenticate
		
		if @user.nil?
			flash[:notice] = t(:login_error)
			render :action => 'start'
		elsif @user.auth_source.type == 'AuthSourceLocal'
			@name = session[:name]
		else
			reset_session
			flash[:notice] = 'User managed externally. Please contact your administration'	# TODO:: translations
			render :action => 'start'
		end
	end
	
	def update
		if session[:user].nil?
			flash[:notice] = t(:login_error)
			render :action => 'start'
		else
			@user = User.find(session[:user])			# Session id as user should only be able to edit themselves.
			if @user.update_attributes(params[:user])
				login_success
			else
				@name = session[:name]
				flash[:notice] = 'Password mismatch. Please try again'	# TODO:: translations
				render :action => 'edit'
			end
		end
	end
	
	
	protected
	
	
	def login_success
		instance_eval &Login.redirection
	end
	
	
	def authenticate
		@username = params[:username]
		account = @username.split(/[\\|\/]+/)
		
		if account.length > 1
			@user = User.try_to_login(account[1], params[:password], AuthSource.where('name = ?', account[0]).first)
		else
			#
			# Find the default authentication source
			#
			auth = AuthSource.order('ordinal ASC').first
			if !auth.nil?
				@user = User.try_to_login(account[0], params[:password], auth)
				@username = "#{auth.name}\\#{@username}"
			end
		end
		
		if !@user.nil?
			#
			# reset to avoid session fixation
			#
			reset_session
			session[:user] = @user.id
			session[:name] = "#{@user.firstname} #{@user.lastname}".strip
			session[:name] = "#{@user.identifier}" if session[:name].empty?
		end
	end
	
end
