class ApplicationController < ActionController::Base
	protect_from_forgery
	before_filter :authenticate
	
	
	protected
	
	
	def authenticate
		redirect_to root_path if session[:user].nil?
	end
	
	
	#
	# Lazy load user information
	#
	def current_user
		@current_user ||= session[:user].nil? ? nil : User.find(session[:user])
	end
	
	def current_user_mail
		@current_mail ||= session[:mail]
	end
	
	def current_user_login
		@current_login ||= session[:login]
	end
end
