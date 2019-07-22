require 'open-uri'
require 'net/http'

# require 'psymine/rest'
# require 'psymine/technical/technical_exception'

namespace :redmine do
	class Connector

		# @example Connecting with Username and Password and fetching Issues
		# Connector.new({:url=> '...', :key=> '...'})
		#
		def initialize(options)
			# Make sure that the uri ends with a '/'
			# cases : uri.com vs uri.com/

			@url = options[:url]
			@key = options[:key]

			if (@url == nil || @key == nil)
				raise "Invalid connector configuration!"
			end

			# @redmine_uri = URI(tmp_uri + "%s.json" % @resource)
		end

		# Provide the API to the REST resource and get info
		# @return String JSON string of the data requested
		def execute(type)

			url = URI(@url + "%s.json?key=%s" % [type.to_s, @key])

			Net::HTTP.start(url.host, url.port) do |http|
				request = Net::HTTP::Get.new(url.request_uri)
				# req[Psymine::Rest::HttpHeader] = @api_key

				response = http.request request
				p response.body
			end

		end

		# # Fetch the information from the Redmine tracker.
		# # @return JSON containing the information that was requested.
		# def fetch!
		# 	if    !@api_key.nil?  || @api_key  != "" then
		# 		fetch_by_api_key
		# 	elsif !@password.nil? || @password != "" ||
		# 		!@username.nil? || @username != "" then
		# 		fetch_by_username_and_password
		# 	end
		# end
		#
		# attr_accessor :api_key, :username, :password
		#
		# private
	end
end

