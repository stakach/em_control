class TokensController < ApplicationController
	
	def authenticate	# Allowed through by application controller
		#
		# Auth(gen)
		# check the system matches (set user and system in session)
		# respond with success
		#
		info = TrustedDevice.try_to_login(params[:key], true)	# true means gen the next key
		if params[:system].present? && params[:system].to_i == info[:system]
			session[:token] = info[:login]
			session[:system] = info[:system]
			session[:key] = params[:key]
			
			render :nothing => true, :layout => false	# success!
		else
			render :nothing => true, :layout => false, :status => :forbidden	# 403
		end
	end
	
	def key
		#
		# Application controller ensures we are logged in
		# grab information out of the session
		# swap the keys
		# respond with success
		#
		
		if session[:token].nil?
			render :text => "no auth", :layout => false
			return
		end
		
		dev = TrustedDevice.where('user_id = ? AND control_system_id = ? AND one_time_key = ? AND expires > ?', 
				session[:token], session[:system], session[:key], Time.now).first
				
		if dev.present? && dev.next_key != dev.one_time_key	# Prevents calling after accepted
			
			render :text => dev.next_key, :layout => false
		else
			render :text => "no auth", :layout => false
		end
	end
	
	
	def accept
		dev = TrustedDevice.where('user_id = ? AND control_system_id = ? AND one_time_key = ? AND expires > ?', 
				session[:token], session[:system], session[:key], Time.now).first
				
		if dev.present? && dev.next_key != dev.one_time_key	# Can only call once
			
			dev.accept_key
			render :nothing => true, :layout => false	# success!
		else
			render :nothing => true, :layout => false, :status => :forbidden	# 403
		end
	end
	
	
	def ask
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
				session[:token] = user.id
				session[:system] = sys.id
				session[:key] = dev.one_time_key
				
				render :text => "{}", :layout => false	# success!
			else
				render :json => dev.errors.messages, :layout => false, :status => :not_acceptable	# 406
			end
		else
			render :text => "{you:'are not authorised'}", :layout => false, :status => :forbidden	# 403
		end
	end
end
