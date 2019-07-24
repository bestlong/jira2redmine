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

		def initialize(xmlPath, connector)
			raise "Argument error blah blah" unless connector.kind_of?(Connector)

			@xml = Nokogiri::XML(File.new(xmlPath + "/" + JIRA_ENTITIES_FILE, 'r:utf-8'),nil,'utf-8'){ |c| c.noblanks }

			if @xml.root.children.count < 1
				raise "Source XML is empty!"
			end

			load_jira_statuses
			load_jira_users
			load_jira_types
			load_jira_priorities
			load_jira_projects
			load_jira_issues

			# load_comments
			# # @comments.each {|k, v| puts("Found comment: [#%08d] author: %s, issue: %s, created: %s" % [k, v.author, v.issue, v.created])}
			# # puts("\n")
			#
			# load_attaches
			# # @comments.each {|k, v| puts("Found attache: [#%08d] author: %s, issue: %s, mimetype: %s, filename: %s, created: %s" % [k, v.author, v.issue, v.mimetype, v.filename, v.created])}
			# # puts("\n")
			
			@connector = connector
		end

		def migrate
			puts "Prepare roles..."
			prepare_roles

			puts "Prepare statuses..."
			if prepare_statuses < 1

				puts "Prepare trackers..."
				if prepare_trackers < 1

					puts "Prepare priorities..."
					if prepare_priorities < 1

						puts "Migrate users..."
						migrate_users

						puts "Migrate projects..."
						migrate_projects

						puts "Migrate issues..."
						migrate_issues

					else
						puts "[Error] Sorry! Undefined priorities found!"
					end
				else
					puts "[Error] Sorry! Undefined trackers found!"
				end
			else
				puts "[Error] Sorry! Undefined statuses found!"
			end

			puts "Finished"
		end

		@@default_role_name = "developer"
		def prepare_roles
			@default_role = @connector.roles.select{|v|
				v[:name].downcase == @@default_role_name}.first

			if @default_role == nil
				raise "No default role found!"
			end
		end

		@@statuses_aliases = {
			"open" => "new",
			"to do" => "new",
			"done" => "resolved",
			"review" => "resolved",
			"rework" => "reworking",
			"reopened" => "reworking"
		}
		def prepare_statuses
			@statuses_binding = {}

			redmine_statuses = @connector.statuses
			count = 0

			@statuses.each do |id, name|
				puts "[JIRA] Status found: %s" % name

				search = name.downcase
				if @@statuses_aliases.key?(search)
					search = @@statuses_aliases[search]
				end

				redmine_status = redmine_statuses.select{|v| v[:name].downcase == search}.first
				if (redmine_status != nil)
					puts "[Redmine] Status assigned: %s!" % redmine_status[:name]
					@statuses_binding[id] = redmine_status[:id]
				else
					puts "[Redmine] Undefined status: %s" % name
					count += 1
				end
			end

			# @statuses_binding.each {|k, v| p "%s: %s" % [k, v]}

			return count
		end

		@@trackers_aliases = {
			"epic" => "feature",
			"story" => "feature",
			"task" => "feature",
			"sub-task" => "support",
		}

		def prepare_trackers
			@trackers_binding = {}

			redmine_trackers = @connector.trackers
			count = 0

			@types.each do |id, name|
				puts "[JIRA] Tracker found: %s" % name

				search = name.downcase
				if @@trackers_aliases.key?(search)
					search = @@trackers_aliases[search]
				end

				redmine_tracker = redmine_trackers.select{|v| v[:name].downcase == search}.first
				if (redmine_tracker != nil)
					puts "[Redmine] Tracker assigned: %s!" % redmine_tracker[:name]
					@trackers_binding[id] = redmine_tracker[:id]
				else
					puts "[Redmine] Undefined tracker: %s" % name
					count += 1
				end
			end

			# @trackers_binding.each {|k, v| p "%s: %s" % [k, v]}
			return count
		end

		@@priorities_aliases = {
			"lowest" => "low",
			"highest" => "urgent",
			"medium" => "normal",
		}
		def prepare_priorities
			@priorities_binding = {}

			redmine_priorities = @connector.priorities
			count = 0

			@priorities.each do |id, name|
				puts "[JIRA] Priority found: %s" % name

				search = name.downcase
				if @@priorities_aliases.key?(search)
					search = @@priorities_aliases[search]
				end

				redmine_priority = redmine_priorities.select{|v| v[:name].downcase == search}.first
				if (redmine_priority != nil)
					puts "[Redmine] Priority assigned: %s!" % redmine_priority[:name]
					@priorities_binding[id] = redmine_priority[:id]
				else
					puts "[Redmine] Undefined priority: %s" % name
					count += 1
				end
			end

			# @priorities_binding.each {|k, v| p "%s: %s" % [k, v]}
			return count
		end

		def load_jira_users
			@users = {}

			get_list_from_tag('/*/User', :id, :userName, :emailAddress, :firstName, :lastName, ).each do |v|
				@users[v['id']] = {:login => v['userName'],
					:mail => v['emailAddress'], :firstname => v['firstName'], :lastname => v['lastName']}
			end
		end

		def migrate_users
			@user_binding = {}
			redmine_users = @connector.users

			@users.each do |id, info|
				puts "[JIRA] Found user: %s" % info[:mail]

				redmine_user = redmine_users.select{|v| v[:mail] == info[:mail] }.first
				if redmine_user != nil
					puts "[Redmine] User already exists: %s" % redmine_user[:mail]
				else
					redmine_user = @connector.create_user info

					if redmine_user == nil
						raise "[Error] Can't create user: %s" % email
					end

					puts "[Redmine] Created user: %s" % redmine_user[:mail]
				end

				@user_binding[id] = redmine_user[:id]
			end

			# @user_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def migrate_projects
			@projects_binding = {}
			redmine_projects = @connector.projects

			@projects.each do |id, info|
				puts "[JIRA] Found project: %s" % info.key

				redmine_project = redmine_projects.select{|v| v[:identifier] == info.key.downcase }.first
				if redmine_project != nil
					puts "[Redmine] User already exists: %s" % redmine_project[:identifier]
				else
					redmine_project = @connector.create_project info.to_h

					if redmine_project == nil
						raise "[Error] Can't create project: %s" % info.key
					end

					puts "[Redmine] Created project: %s" % redmine_project[:identifier]
				end

				@projects_binding[id] = redmine_project[:id]
			end

			# @projects_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def migrate_issues
			@issues_binding = {}

			@issues.each do |id, info|
				puts "[JIRA] Found issue: %s" % info.key

				data = {
					:project_id => @projects_binding[info.project],
					:tracker_id => @trackers_binding[info.type],
					:status_id => @statuses_binding[info.status],
					:priority_id => @priorities_binding[info.priority],
					:subject => info.summary,
					:description => info.description
				}

				redmine_issue = @connector.create_issue data
				if redmine_issue == nil
					raise "[Error] Can't create issue: %s" % info.key
				end

				if info.assignee != nil
					@users.each do |k, u|
						if u[:login] == info.assignee

							membership = @connector.memberships data[:project_id]
							if !membership.include? @user_binding[k]
								@connector.create_membership(@projects_binding[info.project], {
									:user_id => @user_binding[k],
									:role_ids => [@default_role[:id]]
								})
							end

							@connector.update_issue redmine_issue[:id], {:assigned_to_id => @user_binding[k]}
							puts "[Redmine] Issue assigned to %s" % info.assignee
						end
					end

					# p @user_binding[info.assignee]
					# p info.assignee

					# puts "[Redmine] Issue assigned to %s" % info.assignee
				end

				puts "[Redmine] Created issue: %s" % redmine_issue[:id]
				@issues_binding[id] = redmine_issue[:id]
			end

			@projects_binding.each {|k, v| p "%s: %s" % [k, v]}
		end

		def load_jira_statuses
			@statuses = {}

			get_list_from_tag('/*/Status', :name, :id).each do |v|
				@statuses[v['id']] = v['name']
			end
		end

		def load_jira_types
			@types = {}

			get_list_from_tag('/*/IssueType', :name, :id).each do |v|
				@types[v['id']] = v['name']
			end
		end

		def load_jira_priorities
			@priorities = {}

			get_list_from_tag('/*/Priority', :name, :id).each do |v|
				@priorities[v['id']] = v['name']
			end
		end

		def load_jira_projects
			@projects = {}

			get_list_from_tag('/*/Project', :id, :name, :key, :lead, :description).each do |v|
				@projects[v['id']] = JiraProject.new(v)
			end
		end

		def load_jira_issues
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

		private :get_list_from_tag, :load_jira_types, :load_jira_priorities,
			:load_jira_statuses, :load_jira_projects, :load_jira_issues, :load_comments
	end
end