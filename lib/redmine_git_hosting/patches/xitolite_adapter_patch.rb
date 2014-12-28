require_dependency 'redmine/scm/adapters/xitolite_adapter'

module RedmineGitHosting
  module Patches
    module XitoliteAdapterPatch

      def self.included(base)
        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable

          class << self
            alias_method_chain :client_command,                :git_hosting
            alias_method_chain :scm_version_from_command_line, :git_hosting
          end

          alias_method_chain :git_cmd, :git_hosting
        end

      end


      module ClassMethods

        def client_command_with_git_hosting
          @@bin ||= 'git (with sudo)'
        end


        def scm_version_from_command_line_with_git_hosting
          RedmineGitHosting::GitoliteWrapper.sudo_capture('git', '--version', '--no-color')
        rescue => e
          RedmineGitHosting.logger.error("Can't retrieve git version: #{e.output}")
          'unknown'
        end

      end


      module InstanceMethods

        private

          def logger
            RedmineGitHosting.logger
          end


          # Compute string from repo_path that should be same as: repo.git_cache_id
          # If only we had access to the repo (we don't).
          def git_cache_id
            logger.debug("Lookup for git_cache_id with repository path '#{repo_path}' ... ")
            @git_cache_id ||= Repository::Xitolite.repo_path_to_git_cache_id(repo_path)
            logger.warn("Unable to find git_cache_id for '#{repo_path}', bypass cache... ") if @git_cache_id.nil?
            @git_cache_id
          end


          def repo_path
            root_url || url
          end


          def base_args
            [ 'sudo', *RedmineGitHosting::GitoliteWrapper.sudo_shell_params, 'git', '--git-dir', repo_path, *git_args ].clone
          end


          def git_args
            if self.class.client_version_above?([1, 7, 2])
              ['-c', 'core.quotepath=false', '-c', 'log.decorate=no']
            end
          end


          def prepare_command(args)
            # Get our basics args
            full_args = base_args
            # Concat with Redmine args
            full_args += args
            # Quote args
            cmd_str = full_args.map { |e| shell_quote e.to_s }.join(' ')
          end


          def git_cache_enabled?
            max_cache_time > 0
          end


          def max_cache_time
            RedmineGitHosting::Config.get_setting(:gitolite_cache_max_time).to_i
          end


          def git_cmd_with_git_hosting(args, options = {}, &block)
            cmd_str = prepare_command(args)

            if !git_cache_id.nil? && git_cache_enabled?
              # Insert cache between shell execution and caller
              RedmineGitHosting::CacheManager.execute(cmd_str, git_cache_id, options, &block)
            else
              Redmine::Scm::Adapters::AbstractAdapter.shellout(cmd_str, options, &block)
            end
          end

      end

    end
  end
end

unless Redmine::Scm::Adapters::XitoliteAdapter.included_modules.include?(RedmineGitHosting::Patches::XitoliteAdapterPatch)
  Redmine::Scm::Adapters::XitoliteAdapter.send(:include, RedmineGitHosting::Patches::XitoliteAdapterPatch)
end