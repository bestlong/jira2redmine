namespace :jira do
	namespace :model do

		class User < BaseJira

			DEST_MODEL = User
			MAP = {}

			attr_accessor :jira_emailAddress, :jira_name

			def initialize(node)
				super
			end

			def retrieve
				# Check mail address first, as it is more likely to match across systems
				user = self.class::DEST_MODEL.find_by_mail(self.jira_emailAddress)
				if !user
					user = self.class::DEST_MODEL.find_by_login(self.jira_name)
				end

				return user
			end

			def migrate
				super
				$MIGRATED_USERS_BY_NAME[self.jira_name] = self.new_record
			end

			# First Name, Last Name, E-mail, Password
			# here is the tranformation of Jira attributes in Redmine attribues
			def red_firstname
				self.jira_firstName
			end

			def red_lastname
				self.jira_lastName
			end

			def red_mail
				self.jira_emailAddress
			end

			def red_login
				self.jira_name
			end

			def before_save(new_record)
				new_record.login = red_login
				if new_record.new_record?
					new_record.salt_password('Pa$$w0rd')
				end
			end

			def post_migrate(new_record, is_new)
				if is_new
					new_record.update_attribute(:must_change_passwd, true)
					new_record.reload
				end
			end
		end
	end
end