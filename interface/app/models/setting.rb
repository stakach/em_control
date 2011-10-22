
require 'base64'
require 'encryptor'


class Setting < ActiveRecord::Base
	belongs_to :object, :polymorphic => true
	
	after_initialize	:decrypt_setting
	before_save			:do_encrypt_setting
	
	
	protected
	
	
	def decrypt_setting
		return unless self[:encrypt_setting]
		
		if self[:text_value].blank?
			self[:text_value] = ""
		else
			self[:text_value] = Encryptor.decrypt(Base64.decode64(self[:text_value]), {:key => CONTROL_CONFIG[:encrypt_key], :algorithm => 'aes-256-cbc'})
		end
	end
	
	def do_encrypt_setting
		return unless self[:encrypt_setting]
		
		if self[:text_value].blank?
			self[:text_value] = ""
		else
			self[:text_value] = Base64.encode64(Encryptor.encrypt(self[:text_value], {:key => CONTROL_CONFIG[:encrypt_key], :algorithm => 'aes-256-cbc'}))
		end
	end
	
	
	validates_presence_of :name, :object, :value_type
end
