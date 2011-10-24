require 'uri'

class TokensController < ActionController::Base
	protect_from_forgery
	before_filter :auth_user, :except => [:authenticate, :manifest, :new]
	layout nil
	
	
	def authenticate	# Allowed through by application controller
		#
		# Auth(gen)
		# check the system matches (set user and system in session)
		# respond with success
		#
		dev = TrustedDevice.try_to_login(params[:key], true)	# true means gen the next key
		if params[:system].present? && params[:system].to_i == dev.control_system_id
			reset_session unless session[:user].present?
			session[:token] = dev.user_id
			session[:system] = dev.control_system_id
			session[:key] = params[:key]
			cookies.permanent[:next_key] = {:value => dev.next_key, :path => URI.parse(request.referer).path}
			
			render :nothing => true	# success!
		else
			render :nothing => true, :status => :forbidden	# 403
		end
	end
	
	
	def accept
		dev = TrustedDevice.where('user_id = ? AND control_system_id = ? AND one_time_key = ? AND (expires IS NULL OR expires > ?)', 
				session[:token], session[:system], session[:key], Time.now).first
				
		if dev.present?
			dev.accept_key
			render :nothing => true	# success!
		else
			render :nothing => true, :status => :forbidden	# 403
		end
	end
	
	
	#
	# Build a new session for the interface if the existing one has expired
	#	This maintains the csrf security
	#	We don't want to reset the session if a valid user is already authenticated either
	#
	def new
		if session[:user].nil?
			reset_session
		end
		
		render :text => form_authenticity_token
	end
	
	
	def create
		#
		# Application controller ensures we are logged in as real user
		# Ensure the user can access the control system requested (the control system does this too)
		# Generate key, populate the session
		#
		user = current_user	# We have to be authed to get here
		sys = user.control_systems.where('control_systems.id = ? AND active = ?', params[:system], true).first
		if user.present? && sys.present?
			
			dev = TrustedDevice.new(params[:trusted_device])
			dev.user = user
			dev.control_system = sys
			dev.save
			
			if !dev.new_record?
				cookies.permanent[:next_key] = {:value => dev.one_time_key, :path => URI.parse(request.referer).path}
				render :text => "{}"	# success!
			else
				render :json => dev.errors.messages, :status => :not_acceptable	# 406
			end
		else
			render :text => "{you:'are not authorised'}", :status => :forbidden	# 403
		end
	end
	
	
	protected
	
	
	def auth_user
		redirect_to root_path unless session[:user].present? || session[:token].present?
	end
end
