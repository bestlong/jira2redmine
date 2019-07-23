require 'httparty'
require 'open-uri'
require 'json'

namespace :redmine do
	class Connector

		# @example Connecting with Username and Password and fetching Issues
		# Connector.new({:url=> '...', :key=> '...'})
		# Please make sure that the url ends with a '/'
		def initialize(options)
			@url = options[:url]
			@key = options[:key]

			if (@url == nil || @key == nil)
				raise "Invalid connector configuration!"
			end
		end

		def select(type, *attributes)
			response = HTTParty.get(@url + "%s.json" % type.to_s,
				:headers => {"X-Redmine-API-Key" => @key, "Content-Type": "application/json"})

			if response.code != 200
				raise "[Error: %s] Can't reach the API!" % response.code
			end

			return filter JSON.parse(response.body, symbolize_names: true), type, *attributes
		end

		def insert(type, values, *attributes)
			response = HTTParty.post(@url + "%s.json" % type.to_s, :query => values,
				 :headers => {"X-Redmine-API-Key" => @key, "Content-Type" => "application/json"})

			if response.code != 201
				raise "[Error: %s] Can't reach the API!" % response.code
			end

			return JSON.parse(response.body, symbolize_names: true)
		end

		def filter(data, type, *attributes)
			raise "Invalid data!" if !data.is_a?(Hash)

			type = type.to_sym
			if (!data.has_key? type)
				raise "Invalid response!"
			end

			if data[type].is_a?(Array)
				return data[type].map(){|u| u.select(){|k,_v| attributes.empty? || attributes.include?(k)}}
			end

			if data[type].is_a?(Hash)
				return data[type].select(){|k,_v| attributes.empty? || attributes.include?(k)}
			end
		end

		def users
			return select :users, :id, :mail
		end

		def create_user(data)
			return filter insert( :users, {:user => data}, :id, :mail), :user, :id, :mail
		end

		private :select, :insert, :filter
	end
end

