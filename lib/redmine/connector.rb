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

		def select(uri, type, *attributes)
			response = HTTParty.get(@url + "%s.json" % uri,
				:headers => {"X-Redmine-API-Key" => @key, "Content-Type": "application/json"})

			if response.code != 200
				raise "[Error: %s] Can't reach the API!" % response.code
			end

			return filter JSON.parse(response.body, symbolize_names: true), type, *attributes
		end

		def insert(uri, values)
			response = HTTParty.post(@url + "%s.json" % uri, :query => values,
				 :headers => {"X-Redmine-API-Key" => @key, "Content-Type" => "application/json"})

			if response.code != 201
				raise "[Error: %s] Can't reach the API!" % response.code
			end

			return JSON.parse(response.body, symbolize_names: true)
		end

		def update(uri, values)
			response = HTTParty.put(@url + "%s.json" % uri, :query => values,
				 :headers => {"X-Redmine-API-Key" => @key, "Content-Type" => "application/json"})

			if response.code != 200
				p response.code
				p response.body

				raise "[Error: %s] Can't reach the API!" % response.code
			end
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

		def statuses
			return select "/issue_statuses", :issue_statuses, :id, :name
		end

		def trackers
			return select "/trackers", :trackers, :id, :name
		end

		def priorities
			return select "/enumerations/issue_priorities", :issue_priorities, :id, :name
		end

		def users
			return select "/users", :users,:id, :mail
		end

		def projects
			return select "/projects", :projects,:id, :name, :identifier
		end

		def roles
			return select "/roles", :roles,:id, :name
		end

		def memberships(id)
			return  (select "/projects/%s/memberships" % id, :memberships, :user ).map {|v| v[:user][:id]}
		end

		def create_user(data)
			return filter insert( "/users", {:user => data}), :user, :id, :mail
		end

		def create_project(data)
			return filter insert( "/projects", {:project => {:name => data[:name], :identifier => data[:key].downcase}}), :project, :id, :name, :identifier
		end

		def create_issue(data)
			return  filter insert( "/issues", {:issue => data}), :issue, :id
		end

		def create_membership(project, data)
			return filter insert("/projects/%s/memberships" % project, {:membership => data}), :membership, :id
		end

		def update_issue(id, data)
			update( "/issues/%s" % id, {:issue => data})
		end

		private :select, :insert, :filter
	end
end

