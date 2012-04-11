# methods used by tasks defined in tasks.rb
#
# generally this module is 'include'd into a cap
# :namespace, seems to do what we want. 
require 'cap_git_tools'

module CapGitTools::TaskHelpers
   ####
    # Some functions used by the tasks
    #
    
    # say with an indent in spaces
    def say_formatted(msg, options = {})
      options.merge!(:indent => 4)
      Capistrano::CLI.ui.say(' ' * options[:indent] + msg )
    end
    
    # execute a 'git fetch', but mark in a private variable that
    # we have, so we only do it once per cap execution. 
    def ensure_git_fetch
      unless @__git_fetched      
        local_sh "git fetch #{upstream_remote}"
        @__git_fetched = true
      end
    end
    
    # execute locally as a shell command, echo'ing to output, as
    # well as capturing error and aborting. 
    def local_sh(cmd)
      say_formatted("executing locally: #{cmd}")
      `#{cmd}`
      abort("failed: #{cmd}") unless $? == 0
    end
    
    # How to refer to the upstream git repo configured in cap :repository?
    # Will _usually_ return 'origin', will sometimes return another remote,
    # will occasionally return a raw git url when it's not configured in
    # remotes for some reason. 
    #
    # This used to be hard-coded to 'origin'. Then it was configurable.
    # Then I realized it _has_ to be whatever is set in cap :repository.
    # We'll look up the remote alias for that, if available, and cache
    # the lookup. Usually it'll be 'origin',  yeah. 
    def upstream_remote
      @__upstream_remote = begin
        git_url = fetch(:repository)        
        
        remote_info = 
        `git remote -v`.
          split("\n").
          collect {|line| line.split(/[\t ]/) }.
          find {|list| list[1] == git_url }
        
        remote_info ? remote_info[0] : git_url
      end
    end
    
  
    # what branch we're going to tag and deploy -- if cap 'branch' is set,
    # use that one, otherwise use current branch in checkout
    def working_branch
      @__git_working_branch ||= begin
        if exists?("branch")
          fetch(:branch)
        else
          b = `git symbolic-ref -q HEAD`.sub(%r{^refs/heads/}, '').chomp
          b.empty? ? "HEAD" : b
        end
      end
      
    end
    
    # current SHA fingerprint of local branch mentioned in :branch
    def local_sha
      `git log --pretty=format:%H #{working_branch} -1`.chomp
    end
    
    def tag_prefix
      fetch(:tag_prefix, fetch(:stage, "deploy"))
    end
    
    def from_prefix
      fetch("from_prefix", "staging")
    end
  
    
    # mostly used by git:retag, calculate the tag we'll be retagging FROM. 
    #
    # can set cap :from_tag. Or else find last tag matching from_prefix,
    # which by default is "staging-*"
    def from_tag
      t = nil
      if exists?("from_tag")
        t = fetch("from_tag")
      else
        t = fetch_last_tag(  self.from_prefix ) 
      
        if t.nil? || t.empty?
          abort("failed: can't find existing tag matching #{self.from_prefix}-*")
        end
      end
      return t
    end
    
    # find the last (chronological) tag with given prefix. 
    # prefix can include shell-style wildcards like '*'. Defaults to
    # last tag with current default tag_prefix. 
    #
    # Note: Will only work on git 'full' annotated tags (those signed or 
    # with -m message or -a) because git only stores dates for annotated tags.
    # others will end up sorted lexicographically BEFORE any annotated tags. 
    def fetch_last_tag(pattern_prefix = self.tag_prefix)
      # make sure we've fetched to get latest from upstream. 
      ensure_git_fetch
      
      # crazy git command, yeah. Sort by tagged date descending, one line only, 
      # output refname:short, look for tags matching our pattern.  
      last_tag = `git for-each-ref --count=1 --sort='-taggerdate' --format='%(refname:short)' 'refs/tags/#{pattern_prefix}-*' 2>/dev/null`.chomp
      return nil if last_tag == ''
      return last_tag
    end
    
    # show commit lot from commit-ish to commit-ish,
    # using appropriate UI tool. 
    #
    # If you have cap :github_browser_compare set and the remote is github,
    # use `open` to open in browser. 
    #
    # else if you have ENV['git_log_command'] set, pass to `git` (don't know
    # what this is for, inherited from gitflow)
    #
    # else just use an ordinary command line git log   
    def show_commit_log(from_tag, to_tag)
      if fetch("github_browser_compare", false ) && `git config remote.#{upstream_remote}.url` =~ /git@github.com:(.*)\/(.*).git/      
        # be awesome for github, use `open` in browser
        command = "open https://github.com/#{$1}/#{$2}/compare/#{from_tag}...#{to_tag}"
      elsif ENV['git_log_command'] && ENV['git_log_command'].strip != ''
        # use custom compare command if set
        command = "git #{ENV['git_log_command']} #{from_tag}..#{to_tag}"
      else
        # standard git log command
        command = "git log #{from_tag}..#{to_tag}"      
      end
      
      say_formatted "Displaying commits from #{from_tag} to #{to_tag}\n\n"
      local_sh command
      puts "" # newline
    end
      
    
    def calculate_new_tag
      # if capistrano :tag is already set, just use it        
      if exists?("tag")
        return fetch("tag")
      end
      
      # otherwise calculate, based on template
            
      tag_suffix = fetch("tag_template", "%{datetime}")
        
      tag_suffix.gsub!(/\%\{([^}]+)\}/) do 
        case $1
        when 'date'
          Time.now.localtime.strftime('%Y-%m-%d')
        when 'datetime'
          Time.now.localtime.strftime('%Y-%m-%d-%H%M')
        when 'what'
          (@__git_what = Capistrano::CLI.ui.ask("What does this release introduce? (this will be normalized and used in the tag for this release) ").gsub(/[ '"]+/, "_"))
        when 'who'
          `whoami`.chomp
        end
      end
        
      return "#{tag_prefix}-#{tag_suffix}"    
    end
    
    # will prompt to confirm new tag, if :confirm_tag is true, otherwise
    # no-op. 
    def guard_confirm_tag(new_tag)    
      if exists?("confirm_tag") && [true, "true"].include?( confirm_tag )      
        confirmed = Capistrano::CLI.ui.agree("Do you really want to deploy #{new_tag}?") do |q|
          q.default = "no"
        end
        unless confirmed
          abort("exiting, user cancelled.")
        end
      end
    end
    
  
end
