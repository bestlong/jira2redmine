require 'nokogiri'
require 'active_record'

$MAP_PROJECT_ID_TO_PROJECT_KEY = {}
$MAP_ISSUE_TO_PROJECT_KEY = {}

namespace :jira do
	class ExtendedStruct < Struct
		def initialize(params = {})
			params.each do |k,v|
				if self.members.include?(k.to_sym)
					send("#{k}=", v)
				end
			end
		end
	end

	JiraProject = ExtendedStruct.new(:name, :lead, :description, :key)
	JiraIssue = ExtendedStruct.new(:key, :project, :creator, :assignee, :type, :summary, :description, :priority, :status, :created, :updated)
	JiraComment = ExtendedStruct.new(:issue, :author, :body, :created)
	JiraAttache = ExtendedStruct.new(:issue, :author, :mimetype, :filename, :created, :filesize)

	class Exporter
		JIRA_ENTITIES_FILE = 'entities.xml'

		def initialize(xmlPath)
			@xml = Nokogiri::XML(File.new(xmlPath + "/" + JIRA_ENTITIES_FILE, 'r:utf-8'),nil,'utf-8'){ |c| c.noblanks }

			if @xml.root.children.count < 1
				raise "Source XML is empty!"
			end

			load_issue_types
			# @types.each {|k, v| puts("Found issue type: [#%08d] %s" % [k, v])}
			# puts("\n")

			load_issue_statuses
			# @statuses.each {|k, v| puts("Found issue status: [#%08d] %s" % [k, v])}
			# puts("\n")

			load_issue_priorities
			# @priorities.each {|k, v| puts("Found issue priority: [#%08d] %s" % [k, v])}
			# puts("\n")

			load_projects
			# @projects.each {|k, v| puts("Found project: [#%08d] name: %s, key: %s, owner: %s" % [k, v.name, v.key, v.lead])}
			# puts("\n")

			load_issues
			# @issues.each {|k, v| puts("Found issue: [#%08d] key: %s, creator: %s, assignee: %s" % [k, v.key, v.creator, v.assignee])}
			# puts("\n")

			load_comments
			# @comments.each {|k, v| puts("Found comment: [#%08d] author: %s, issue: %s, created: %s" % [k, v.author, v.issue, v.created])}
			# puts("\n")

			load_attaches
			# @comments.each {|k, v| puts("Found attache: [#%08d] author: %s, issue: %s, mimetype: %s, filename: %s, created: %s" % [k, v.author, v.issue, v.mimetype, v.filename, v.created])}
			# puts("\n")
		end

		def migrate

		end

		def load_issue_types
			@types = {}

			get_list_from_tag('/*/IssueType', :name, :id).each do |v|
				@types[v['id']] = v['name']
			end
		end

		def load_issue_statuses
			@statuses = {}

			get_list_from_tag('/*/Status', :name, :id).each do |v|
				@statuses[v['id']] = v['name']
			end
		end

		def load_issue_priorities
			@priorities = {}

			get_list_from_tag('/*/Priority', :name, :id).each do |v|
				@priorities[v['id']] = v['name']
			end
		end

		def load_projects
			@projects = {}

			get_list_from_tag('/*/Project', :id, :name, :key, :lead, :description).each do |v|
				@projects[v['id']] = JiraProject.new(v)
			end
		end

		def load_issues
			@issues = {}
			get_list_from_tag('/*/Issue', :id, :key, :project, :creator, :assignee, :type,
				:summary, :description, :priority, :status, :created, :updated).each do |v|
					@issues[v['id']] = JiraIssue.new(v)
			end
		end

		def load_comments
			@comments = {}
			get_list_from_tag('/*/Action[@type="comment"]', :id, :issue, :author, :body, :created).each do |v|
				if v['body'].to_s.length > 0
					@comments[v['id']] = JiraComment.new(v)
				end
			end
		end


		def load_attaches
			@comments = {}
			get_list_from_tag('/*/FileAttachment', :id, :issue, :author, :mimetype, :filename, :created, :filesize).each do |v|
				@comments[v['id']] = JiraAttache.new(v)
			end
		end

		def get_list_from_tag(query, *attributes)
			ret = []

			@xml.xpath(query).each {|node|
				ret.push(Hash[node.attributes.select() { |k, _v|
					attributes.empty? || attributes.include?(k.to_sym)}.map { |k,v| [k,v.content]}])}

			return ret
		end

		private :get_list_from_tag, :load_issue_types, :load_issue_priorities,
			:load_issue_statuses, :load_projects, :load_issues, :load_comments
	end
end