module RedmineHelpdesk
  module MailerPatch
    def self.included(base) # :nodoc:
      base.send(:include, InstanceMethods)
      
      base.class_eval do
        alias_method :issue_edit_without_helpdesk, :issue_edit
        alias_method :issue_edit, :issue_edit_with_helpdesk
	#wicky.sn
        alias_method :issue_add_without_helpdesk, :issue_add
        alias_method :issue_add, :issue_add_with_helpdesk
	#wicky.en
      end
    end
	
    module InstanceMethods

		#wicky.sn
		def logger
			Rails.logger
		end

	#wicky.sn: insert inline image 
	def insert_inline_image(issue, journal)
		Rails.logger.info "insert_inline_image called"
		image_list = ['image/png', 'image/jpg', 'image/gif', 'image/jpeg']
		if issue.attachments.any? 
			issue.attachments.each do |a|
				begin
				#Rails.logger.info "insert_inline_image: attachment=#{a.filename}"
				image_tag = "!#{a.filename}!"
				if (image_list.include? a.content_type) 				
					if issue.description.present? && (issue.description.include? image_tag)
						attachments.inline[a.filename] = File.read(a.diskfile)
						image_url = attachments.inline[a.filename].url
						issue.description = issue.description.gsub(image_tag, "<img src='#{image_url}' />")
					else
						if !journal.present? 
							attachments[a.filename] = File.read(a.diskfile)
						end
					end
					if journal.present? && journal.notes.present? && (journal.notes.include? image_tag)
						attachments.inline[a.filename] = File.read(a.diskfile)
						image_url = attachments.inline[a.filename].url
						journal.notes = journal.notes.gsub(image_tag, "<img src='#{image_url}' />")
					end
				else
					if !journal.present? 
						attachments[a.filename] = File.read(a.diskfile)
					end
				end
			  #rescue
				# ignore rescue
			  end
			end
		end
		if journal.present? && journal.notes.present?
		  journal.details.each do |d|
			if d.property == 'attachment'
			  a = Attachment.find(d.prop_key)
			  begin
				image_tag = "!#{a.filename}!"
				if (image_list.include? a.content_type) && (journal.notes.include? image_tag)
				  attachments.inline[a.filename] = File.read(a.diskfile)
				  image_url = attachments.inline[a.filename].url
				  journal.notes = journal.notes.gsub(image_tag, "<img src='#{image_url}' />")
				else 
					attachments[a.filename] = File.read(a.diskfile)
				end
			  #rescue
				# ignore rescue
			  end
			end
		  end
		end
	end
	#wicky.en


		#wicky.sn
		def issue_add_with_helpdesk(user, issue)
			Rails.logger.info "issue_add_with_helpdesk called"
			redmine_headers 'Project' => issue.project.identifier,
							'Issue-Tracker' => issue.tracker.name,
							'Issue-Id' => issue.id,
							'Issue-Author' => issue.author.login
			redmine_headers 'Issue-Assignee' => issue.assigned_to.login if issue.assigned_to
			message_id issue
			references issue
			@author = issue.author
			@issue = issue
			@user = user
			@issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
			subject = "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}]"
			subject += " (#{issue.status.name})" if Setting.show_status_changes_in_mail_subject?
			subject += " #{issue.subject}"
			
			#wicky.sn: insert inline image 
			insert_inline_image(issue, nil)
			#wicky.en
			
			mail :to => user,
			  :subject => subject
		end	
		#wicky.en
		
		  # Overrides the issue_edit method which is only
		  # be called on existing tickets. We will add the
		  # User Email to the recipients only if no email-
		  # footer text is available.
		  def issue_edit_with_helpdesk(user, journal)
			Rails.logger.info "issue_edit_with_helpdesk called"
			issue = journal.journalized
			redmine_headers 'Project' => issue.project.identifier,
							'Issue-Id' => issue.id,
							'Issue-Author' => issue.author.login,
							'Issue-Tracker' => issue.tracker
			redmine_headers 'Issue-Assignee' => issue.assigned_to.login if issue.assigned_to
			message_id journal
			references issue
			@author = journal.user

			# process reply-separator
			f = CustomField.find_by_name('helpdesk-reply-separator')
			reply_separator = issue.project.custom_value_for(f).try(:value)
			if !reply_separator.blank? and !journal.notes.nil?
			  journal.notes = journal.notes.gsub(/#{reply_separator}.*/m, '')
			  journal.save(:validate => false)
			end

			# add User Email to the recipients
			alternative_user = nil
			
			begin
			  if journal.send_to_owner == true		  
				f = CustomField.find_by_name('helpdesk-email-footer')
				p = issue.project
				owner_email = issue.custom_value_for( CustomField.find_by_name('User Email') ).value
				if !owner_email.blank? && !f.nil? && !p.nil? && p.custom_value_for(f).try(:value).blank?
				  #wicky.sn
				  #alternative_user = owner_email
				  #alternative_user = User.new({:firstname => owner_email, :lastname=>" ",:mail=>owner_email, :id => User.anonymous.id})
				  alternative_user = User.anonymous
				  #wicky.en
				end
			  end
			rescue Exception => e
			  logger.error "Error while adding User Email to recipients of email notification: \"#{e.message}\"."
			end

			# any cc handling needed?
			cc_users = nil
			begin
			  # any cc handling needed?
			  if alternative_user.present?
				custom_field = CustomField.find_by_name('cc-handling')
				custom_value = CustomValue.where(
				  "customized_id = ? AND custom_field_id = ?", issue.project.id, custom_field.id
				).first
				cc_users = custom_value.value.split(',').map(&:strip) if custom_value.value.present?
			  end
			rescue Exception => e
			  logger.error "Error while adding cc-users to recipients of email notification: \"#{e.message}\"."
			end

		  #wicky.sn: insert inline image 
		  insert_inline_image(issue, journal)
		  #wicky.en

			s = "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] "
			s << "(#{issue.status.name}) " if journal.new_value_for('status_id')
			s << issue.subject
			u = (alternative_user.present? ? alternative_user : user)
			@issue = issue
			@user = u
			@journal = journal
			@journal_details = journal.visible_details
			@issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue, :anchor => "change-#{journal.id}")

			mail(
			  :to => u,
			  :cc => cc_users,
			  :subject => s
			)
		  end
	  
    end # module InstanceMethods
  end # module MailerPatch
end # module RedmineHelpdesk

# Add module to Mailer class
Mailer.send(:include, RedmineHelpdesk::MailerPatch)
