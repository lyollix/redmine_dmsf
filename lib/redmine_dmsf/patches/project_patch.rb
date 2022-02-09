# encoding: utf-8
# frozen_string_literal: true
#
# Redmine plugin for Document Management System "Features"
#
# Copyright © 2011    Vít Jonáš <vit.jonas@gmail.com>
# Copyright © 2012    Daniel Munn <dan.munn@munnster.co.uk>
# Copyright © 2011-22 Karel Pičman <karel.picman@kontron.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

module RedmineDmsf
  module Patches
    module ProjectPatch

      ##################################################################################################################
      # Overridden methods

      def initialize(attributes=nil, *args)
        super
        if new_record?
          self.watcher_user_ids = []
        end
      end

      def copy(project, options={})
        super(project, options)
        project = project.is_a?(Project) ? project : Project.find(project)
        to_be_copied = %w(dmsf dmsf_folders approval_workflows)
        to_be_copied = to_be_copied & Array.wrap(options[:only]) unless options[:only].nil?
        if save
          to_be_copied.each do |name|
            send "copy_#{name}", project
          end
          save
        else   
          false
        end
      end

      ##################################################################################################################
      # New methods
      def self.prepended(base)
        base.class_eval do
          has_many :dmsf_files, -> { where(dmsf_folder_id: nil).order(:name) },
            class_name: 'DmsfFile', foreign_key: 'project_id', dependent: :destroy
          has_many :dmsf_folders, ->{ where(dmsf_folder_id: nil).order(:title) },
            class_name: 'DmsfFolder', foreign_key: 'project_id', dependent: :destroy
          has_many :dmsf_workflows, dependent: :destroy
          has_many :folder_links, -> { where dmsf_folder_id: nil, target_type: 'DmsfFolder' },
            class_name: 'DmsfLink', foreign_key: 'project_id', dependent: :destroy
          has_many :file_links, -> { where dmsf_folder_id: nil, target_type: 'DmsfFile' },
            class_name: 'DmsfLink', foreign_key: 'project_id', dependent: :destroy
          has_many :url_links, -> { where dmsf_folder_id: nil, target_type: 'DmsfUrl' },
            class_name: 'DmsfLink', foreign_key: 'project_id', dependent: :destroy
          has_many :dmsf_links, -> { where dmsf_folder_id: nil },
            class_name: 'DmsfLink', foreign_key: 'project_id', dependent: :destroy

          acts_as_watchable

          before_save :set_default_dmsf_notification

          validates_length_of :dmsf_description, maximum: 65535

          const_set(:ATTACHABLE_DMS_AND_ATTACHMENTS, 1)
          const_set(:ATTACHABLE_ATTACHMENTS, 2)
        end
      end

      def set_default_dmsf_notification
        if self.new_record?
          if !self.dmsf_notification && Setting.plugin_redmine_dmsf['dmsf_default_notifications'].present?
            self.dmsf_notification = true
          end
        end
      end

      def dmsf_count
        file_count = DmsfFile.visible.where(project_id: id).all.size
        folder_count = DmsfFolder.visible.where(project_id: id).all.size
        { files: file_count, folders: folder_count }
      end

      # Simple yet effective approach to copying things
      def copy_dmsf(project)
        copy_dmsf_folders project, true
        project.dmsf_files.visible.each do |f|
          f.copy_to self, nil
        end
        project.file_links.visible.each do |l|
          l.copy_to self, nil
        end
        project.url_links.visible.each do |l|
          l.copy_to self, nil
        end
      end

      def copy_dmsf_folders(project, copy_files = false)
        project.dmsf_folders.visible.each do |f|
          f.copy_to self, nil, copy_files
        end
        project.folder_links.visible.each do |l|
          l.copy_to self, nil
        end

      end

      def copy_approval_workflows(project)
        project.dmsf_workflows.each do |wf|
          wf.copy_to self
        end
      end

      # Go recursively through the project tree until a dmsf enabled project is found
      def dmsf_available?
        return true if(visible? && module_enabled?(:dmsf))
        children.each do |child|
          return true if child.dmsf_available?
        end
        false
      end

    end

  end
end

RedmineExtensions::PatchManager.register_model_patch 'Project',
    'RedmineDmsf::Patches::ProjectPatch', prepend: true