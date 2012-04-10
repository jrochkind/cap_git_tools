# Written using crazy meta-code cribbed from capistrano_ext so you
# can (and must) 'require' this file rather than 'load' it.
require 'capistrano'

unless Capistrano::Configuration.respond_to?(:instance)
  abort "cap_git_tools requires Capistrano 2"
end

require 'cap_git_tools/task_helpers'

# yes, oddly this is the only way I can figure out to make
# our task helper methods available to our task, without putting
# em in this file literally. Yes, this means they'll be avail
# to all tasks, not just ones in our namespace, sorry. 
Capistrano::Configuration.send(:include, CapGitTools::TaskHelpers)

Capistrano::Configuration.instance.load do  

    
  namespace :git do
    
    desc <<-DESC
      Ensure git working copy has no uncommitted changes, or abort. 
         
      If cap :branch is set, will also ensure git working copy is on same
      branch as :cap branch. 
     
      The idea is to make sure you're deploying what you're looking at.      
      See also git:guard_upstream, you often want to use both to ensure
      this. 
      
        before "git:tag", "git:check_committed", "git:check_upstream"
      or
        before "deploy",  , "git:check_committed", "git:check_upstream"
     
      setting cap :skip_guard_committed to true will skip even if task is 
      invoked. (eg, `cap deploy -s skip_guard_upstream=true`) 
    DESC
    task :guard_committed do
      if [true, "true"].include? fetch("skip_guard_committed", false)
        say_formatted("Skipping git:guard_committed")
      else  
        if exists?("branch")
          working_branch = `git symbolic-ref -q HEAD`.sub(%r{^refs/heads/}, '').chomp
          unless fetch("branch") == working_branch
            abort %Q{failed: guard_clean: wrong branch
    
        You have configured to deploy from branch ::#{fetch("branch")}::
        but your git working copy is on branch ::#{working_branch}::
    
            git checkout #{fetch("branch")}
    
        and try again. Or, to skip this check, execute cap again with:
            
            -s skip_guard_committed=true    
            }
          end
        end
        
        # cribbed from bundle release rake task
        `git diff HEAD --exit-code` 
        return_code = $?.to_i
        if return_code == 0
          say_formatted("guard_clean: passed")
        else
          abort %Q{failed: guard_clean: uncomitted changes
    
    There are files that need to be committed first.
        
    Or, to skip this check, execute cap again with:        
       -s skip_guard_committed=true  
          }
        end
      end
    end
  
    desc <<-DESC
      Make sure local repo has been pushed to upstream, or abort cap
     
      * Assumes upstream remote is 'origin', or set :upstream_remote
      * Looks in :branch (default 'master') to see what branch should be checked,
        Assumes local :branch tracks upstream_remote/branch
        
      The idea is to ensure what you're deploying is what you're looking at.
      See also git:guard_committed, you usually want to use both to ensure this. 
      
        before "git:tag", "git:check_committed", "git:check_upstream"
      or
        before "deploy",  , "git:check_committed", "git:check_upstream"

      setting cap :skip_guard_upstream to truewill skip even if task is invoked.
      (eg, `cap deploy -s skip_guard_upstream=true`) 
    DESC
    task :guard_upstream do   
      if [true, "true"].include? fetch("skip_guard_upstream", false)
        say_formatted("Skipping git:guard_upstream")
      else      
  
        ensure_git_fetch
        
        remote_sha = `git log --pretty=format:%H #{upstream_remote}/#{working_branch} -1`.chomp
        
        unless local_sha == remote_sha
          abort %Q{failed:
    Your local #{working_branch} branch is not up to date with #{upstream_remote}/#{working_branch}.
    This will likely result in deploying something other than you expect.
    
    Please make sure you have pulled and pushed all code before deploying:
    
        git pull #{upstream_remote} #{working_branch}
        # run tests, etc
        git push #{upstream_remote} #{working_branch}
    
    Or, to skip this check run cap again with `-s skip_guard_upstream=true`
          }
        end
        
        say_formatted("guard_upstream: passed")
      end
    end
    
    desc <<-DESC
      Tags the current checkout and pushes tag to remote.
      
      * tag will be prefix-timestamp
        * if using multi-stage or otherwise setting :stage, prefix defaults
          to :stage   
        * otherwise prefix defaults to 'deploy'
        * or set explicitly with :tag_prefix
     
       sets :branch to the new tag, so subsequent cap deploy tasks will use it
     
       pushes new tag to 'origin' or cap :upstream_remote
       
       You may want to use this with git:guard_committed and/or git:guard_upstream
       to be sure you're deploying what you're looking at:
       before "git:tag", "git:guard_committed", "git:guard_upstream"
    DESC
    task :tag do    
      
      # make sure we have any other deployment tags that have been pushed by
      # others so our auto-increment code doesn't create conflicting tags
      ensure_git_fetch
  
      tag = calculate_new_tag
      
      commit_msg = @__git_what || "cap git:tag: #{tag}"
      
      # tag 'working_branch', means :branch if set, otherwise
      # current working directory checkout. 
      local_sh "git tag -a -m '#{commit_msg}' #{tag} #{self.working_branch}"
  
      # Push new tag back to origin
      local_sh "git push -q #{upstream_remote} #{tag}"
      
      # set :branch to tag, so cap will continue on to deploy the tag we just created!    
      set(:branch, tag)
    end
    
    # takes an already existing tag, and retags it and deploys that tag.
    #
    # usually used in git multistage for moving from staging to production
    #
    # * by default, retags latest already existing tag beginning "staging-". 
    #   * set :from_tag for exact tag (or other commit-ish thing) to re-tag
    #     and deploy 
    #   * set :from_prefix to instead lookup last tag with that prefix,
    #     and re-tag and deploy that one.
    # * by default, sets new tag using the same default rules at git:tag,
    #   ie, set :tag, or will calculate using :tag_prefix, or current stage, or 
    #   'deploy' + timestamp or tag_suffix template 
    #
    #  sets :branch to the new tag, so subsequent cap deploy tasks will use it
    #
    #  pushes new tag to 'origin' or cap :upstream_remote
    task :retag do
      from_tag = self.from_tag
      
      to_tag = calculate_new_tag
      
      self.guard_confirm_tag(from_tag)
      
      say_formatted("git:retag taking #{from_tag} and retagging as #{to_tag}")
      
      local_sh "git tag -a -m 'tagging #{from_tag} for deployment as #{to_tag}' #{to_tag} #{from_tag}"
      
      # Push new tag back to origin
      local_sh "git push -q #{upstream_remote} #{to_tag}"
        
      set(:branch, to_tag)
    end
    
    desc <<-DESC
      Show 5 most recent tags, oldest first 
     
      matching tag_prefix pattern, with some git info about those tags. 
    
      tag_prefix defaults to cap :stage, or "deploy-", or set in cap :tag_prefix
     
      in newer versions of git you could prob do this with a git-log instead with
      certain arguments, but my version doesn't support --tags arg properly yet. 
    DESC
    task :show_tags do    
      system "git for-each-ref --count=4 --sort='-taggerdate' --format='\n* %(refname:short)\n    Tagger: %(taggeremail)\n    Date: %(taggerdate)\n\n    %(subject)' 'refs/tags/#{tag_prefix}-*' "
    end
    
  
    desc <<-DESC
    Show log between most tagged deploy and what will be deployed now. 
    
     less flexible than most of our other tasks, assumes certain workflow. 
     if you're in multi-stage and stage :production, then commit log
     between last production-* tag and last staging-* tag. 
    
     otherwise (for 'staging' or non-multistage) from current branch to
     last staging tag. 
     
     This gets confusing so abstract with all our config, may do odd
     things with custom config, not sure.
    DESC
    task :commit_log do
      from, to = nil, nil
      
      if exists?("stage") && stage.to_s == "production"
        from =  from_tag # last staging-* tag, or last :from_prefix tag
        to = fetch_last_tag # last deploy-* tag, or last :tag_prefix tag
      else
        from = fetch_last_tag # last deploy-* tag, or last :tag_prefix tag
        to = local_sha.slice(0,8)
      end
      
      show_commit_log(from, to)
    end
    
    
    
  end
  
  
end