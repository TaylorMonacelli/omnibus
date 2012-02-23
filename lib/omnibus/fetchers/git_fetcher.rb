module Omnibus

  # Fetcher implementation for projects in git.
  class GitFetcher < Fetcher

    attr_reader :source
    attr_reader :project_dir
    attr_reader :version

    def initialize(software)
      @source       = software.source
      @project_dir  = software.project_dir
      @version      = software.version
    end

    def description
      s=<<-E
repo URI:       #{@source[:git]}
local location: #{@project_dir}
E
    end

    def fetch
      if existing_git_clone?
        fetch_updates unless current_rev_matches_target_rev?
      else
        clone
        checkout
      end
    rescue Exception => e
      ErrorReporter.new(e, self).explain("Failed to fetch git repository '#{@source[:git]}'")
      raise
    end

    private

    def clone
      puts "cloning the source from git"
      clone_cmd = "git clone #{@source[:git]} #{project_dir}"
      shell = Mixlib::ShellOut.new(clone_cmd, :live_stream => STDOUT)
      shell.run_command
      shell.error!
    end

    def checkout
      sha_ref = target_revision

      checkout_cmd = "git checkout #{sha_ref}"
      shell = Mixlib::ShellOut.new(checkout_cmd, :live_stream => STDOUT, :cwd => project_dir)
      shell.run_command
      shell.error!
    end

    def fetch_updates
      puts "fetching updates and resetting to revision #{target_revision}"
      fetch_cmd = "git fetch origin && git fetch origin --tags && git reset --hard #{target_revision}"
      shell = Mixlib::ShellOut.new(fetch_cmd, :live_stream => STDOUT, :cwd => project_dir)
      shell.run_command
      shell.error!
    end

    def existing_git_clone?
      File.exist?("#{project_dir}/.git")
    end

    def current_rev_matches_target_rev?
      current_revision && current_revision.strip.to_i(16) == target_revision.strip.to_i(16)
    end

    def current_revision
      @current_rev ||= begin
                         rev_cmd = "git rev-parse HEAD"
                         shell = Mixlib::ShellOut.new(rev_cmd, :live_stream => STDOUT, :cwd => project_dir)
                         shell.run_command
                         shell.error!
                         output = shell.stdout

                         sha_hash?(output) ? output : nil
                       end
    end

    def target_revision
      @target_rev ||= begin
                        if sha_hash?(version)
                          version
                        else
                          revision_from_remote_reference(version)
                        end
                      end
    end

    def sha_hash?(rev)
      rev =~ /^[0-9a-f]{40}$/
    end

    def revision_from_remote_reference(ref)
      # execute `git ls-remote`
      cmd = "git ls-remote origin #{ref}"
      shell = Mixlib::ShellOut.new(cmd, :live_stream => STDOUT, :cwd => project_dir)
      shell.run_command
      shell.error!
      stdout = shell.stdout

      # parse the output for the git SHA
      unless stdout =~ /^([0-9a-f]{40})\s+(\S+)/
        raise "Could not parse SHA reference"
      end
      return $1
    end
  end
end
