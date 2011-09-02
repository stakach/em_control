class AuthenticationController < ApplicationController
	
	layout 'login'
	
	
	def start
		if !session[:user].nil?
			login_success
		end
	end


	def login
		attr = User.try_to_login(params[:username], params[:password])
		
		if attr.nil?
			flash[:notice] = 'invalid user or password'
			render :action => 'start'
		else
			#
			# reset to avoid session fixation
			#
			reset_session
			session[:user] = attr[:login]
			session[:mail] = attr[:mail] || params[:username]
			session[:login] = params[:username]
			
			#Perform redirect (application defined)
			login_success
		end
	end
	
	
	def logout
		reset_session
		flash[:notice] = 'logged out'
		redirect_to root_path
	end
	
	
	protected
	
	
	def login_success
		instance_eval &Login.redirection
	end
	
end
