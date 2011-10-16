require 'uri'

class TokensController < ApplicationController
	
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
			
			render :nothing => true, :layout => false	# success!
		else
			render :nothing => true, :layout => false, :status => :forbidden	# 403
		end
	end
	
	
	def accept
		dev = TrustedDevice.where('user_id = ? AND control_system_id = ? AND one_time_key = ? AND (expires IS NULL OR expires > ?)', 
				session[:token], session[:system], session[:key], Time.now).first
				
		if dev.present?
			dev.accept_key
			render :nothing => true, :layout => false	# success!
		else
			render :nothing => true, :layout => false, :status => :forbidden	# 403
		end
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
				render :text => "{}", :layout => false	# success!
			else
				render :json => dev.errors.messages, :layout => false, :status => :not_acceptable	# 406
			end
		else
			render :text => "{you:'are not authorised'}", :layout => false, :status => :forbidden	# 403
		end
	end
end
