class ApplicationController < ActionController::Base
	protect_from_forgery
	before_filter :authenticate, :except => [:display]
	
	
	protected
	
	
	def authenticate
		if session[:user].nil?
			redirect_to root_path
		else
			#
			# This allows admins to act as a user if they so desire
			#	Logs will show which user actually made changes however
			#
			@current_user = User.find(session[:user])
			@current_email = session[:mail]
		end
	rescue
		redirect_to logout_url
	end
end
